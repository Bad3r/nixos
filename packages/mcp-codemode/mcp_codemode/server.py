# Copyright (c) 2026 Bad3r

"""Downstream MCP JSON-RPC 2.0 server exposing search and execute Code Mode tools."""

from __future__ import annotations

import contextlib
import json
import queue
import signal
import sys
import threading
import time
from dataclasses import dataclass, replace
from typing import TYPE_CHECKING

from ._util import (
    PACKAGE_INFO,
    PROTOCOL_VERSION,
    RPC_METHOD_NOT_FOUND,
    SUPPORTED_PROTOCOL_VERSIONS,
    as_dict,
    as_dict_list,
    is_valid_rpc_id,
)
from .config import (
    DISABLE_ENV_VAR,
    ENABLE_ENV_VAR,
    Manifest,
    resolve_enabled_servers,
    user_overrides_path,
)
from .sandbox import (
    SandboxConfig,
    SandboxError,
    run_sandbox,
    truncate_text,
)
from .upstream import UpstreamError, UpstreamSupervisor

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

NON_TEXT_BLOCK_TYPES = frozenset({"image", "audio", "resource", "resource_link"})
RPC_INVALID_PARAMS = -32602
RPC_INTERNAL_ERROR = -32603
RPC_DEADLINE_HEADROOM_SEC = 3.0
UNFILTERED_DISCOVERY_TIMEOUT_SEC = 45.0
SHUTDOWN_JOIN_SEC = 2.0
MAX_ATTACHMENTS = 16
MAX_CONCURRENT_REQUESTS = 8
MAX_PENDING_REQUESTS = 64
MAX_DISCOVERY_WORKERS = 6


class ToolDispatchError(RuntimeError):
    """Raised when a sandboxed Code Mode RPC call cannot proceed."""

    @classmethod
    def unknown_server(cls, server: str) -> ToolDispatchError:
        """Create an error for an unknown server name."""
        return cls(f"unknown MCP server '{server}'")

    @classmethod
    def disabled_server(cls, server: str) -> ToolDispatchError:
        """Create an error explaining how to enable an opt-in server."""
        return cls(
            f"MCP server '{server}' is disabled. Enable it without restarting via "
            f"`mcp-codemode enable {server}` (run from the project directory; writes a "
            f"project-scoped entry in {user_overrides_path()}) or "
            f"`mcp-codemode enable --user {server}` (user-wide; required for GUI clients "
            f"that launch outside the workspace directory), or launch the client with "
            f"`{ENABLE_ENV_VAR}={server}`."
        )

    @classmethod
    def unsupported_method(cls, mode: str, method: str) -> ToolDispatchError:
        """Create an error when sandboxed code calls a disallowed RPC method."""
        return cls(f"method '{method}' is not available in '{mode}' mode")

    @classmethod
    def missing_server_or_tool(cls) -> ToolDispatchError:
        """Create an error when call_tool omits server or tool."""
        return cls("call_tool requires non-empty 'server' and 'tool'")

    @classmethod
    def upstream_tool_error(cls, server: str, tool: str, detail: str) -> ToolDispatchError:
        """Create an error when an upstream tool returns isError=true."""
        return cls(f"{server}.{tool}: {detail}")


def _collect_blocks(
    raw_content: object,
    attachments: list[dict[str, object]],
    attachments_lock: threading.Lock,
) -> tuple[list[str], list[dict[str, object]]]:
    text_parts: list[str] = []
    non_text_meta: list[dict[str, object]] = []
    for block in as_dict_list(raw_content):
        btype = block.get("type")
        if btype == "text":
            text_parts.append(str(block.get("text", "")))
        elif isinstance(btype, str) and btype in NON_TEXT_BLOCK_TYPES:
            with attachments_lock:
                if len(attachments) < MAX_ATTACHMENTS:
                    attachments.append(block)
            meta: dict[str, object] = {"type": btype}
            nested = as_dict(block.get("resource")) if btype == "resource" else None
            for field_name in ("mimeType", "uri"):
                if field_name in block:
                    meta[field_name] = block[field_name]
                elif nested is not None and field_name in nested:
                    meta[field_name] = nested[field_name]
            non_text_meta.append(meta)
    return text_parts, non_text_meta


def _parse_text_or_json(joined: str) -> object:
    if not joined.strip():
        return joined
    try:
        parsed: object = json.loads(joined)
    except json.JSONDecodeError:
        return joined
    return parsed


def _unwrap_upstream_result(
    result: dict[str, object],
    attachments: list[dict[str, object]],
    attachments_lock: threading.Lock,
) -> object:
    text_parts, non_text_meta = _collect_blocks(
        result.get("content"), attachments, attachments_lock
    )
    structured = result.get("structuredContent")

    if structured is not None and not non_text_meta:
        return structured

    joined = "\n".join(text_parts)
    parsed_text = _parse_text_or_json(joined)

    if non_text_meta:
        payload: dict[str, object] = {"attachments": non_text_meta}
        if structured is not None:
            payload["structuredContent"] = structured
        elif joined:
            payload["result"] = parsed_text
        return payload

    if text_parts:
        return parsed_text
    return result


def _extract_error_text(result: dict[str, object]) -> str:
    parts = [
        str(block.get("text", ""))
        for block in as_dict_list(result.get("content"))
        if block.get("type") == "text"
    ]
    joined = "\n".join(part for part in parts if part)
    return joined or json.dumps(result)


def _compact_tool_entry(tool: dict[str, object]) -> dict[str, object]:
    return {
        "name": tool.get("name", ""),
        "description": tool.get("description", ""),
    }


def _format_execution_text(value: object, logs: list[str]) -> str:
    sections: list[str] = []
    if logs:
        sections.append("Console output:\n" + "\n".join(logs))
    if value is not None:
        if isinstance(value, str):
            sections.append(value)
        else:
            sections.append(json.dumps(value, indent=2, ensure_ascii=False))
    elif not logs:
        sections.append("null")
    return truncate_text("\n\n".join(sections))


def _rpc_deadline(sandbox_deadline: float) -> float:
    remaining = sandbox_deadline - time.monotonic()
    if remaining > RPC_DEADLINE_HEADROOM_SEC + 1.0:
        return sandbox_deadline - RPC_DEADLINE_HEADROOM_SEC
    return sandbox_deadline


def _build_tool_definitions(manifest: Manifest) -> list[dict[str, object]]:
    server_list = ", ".join(
        f"{spec.alias} ({spec.name})" if spec.alias != spec.name else spec.name
        for spec in manifest.servers.values()
    )
    search_desc = (
        "Inspect available MCP servers and their tool schemas in a read-only JS/TS sandbox "
        f"without loading all tool schemas into context. Configured servers: {server_list}. "
        "Write `async () => { ... }` using `await codemode.servers()` "
        "(lists servers, aliases, and enabled/disabled status), "
        "`await codemode.tools(server?, { refresh? })` (compact tool names and descriptions; "
        "prefer passing a specific `server` to avoid launching unrelated servers), "
        "and `await codemode.spec(server?, { refresh? })` (full JSON input schemas)."
    )
    exec_desc = (
        "Execute JS/TS in an isolated zero-network, zero-filesystem sandbox with access to "
        "enabled MCP servers via `codemode.<server>.<tool>(args)` (use underscore aliases such as "
        "`cloudflare_api` for hyphenated server names) or `codemode.call(server, tool, args)`, "
        "plus `await codemode.servers()`, `await codemode.tools()`, and `await codemode.spec()`. "
        "Use `search` first to inspect schemas. Return only the filtered result you need; output "
        "past 24,000 chars is truncated. Toggle opt-in servers without restarting the client via "
        f"`mcp-codemode enable <server>` (run from the project directory; writes to "
        f"{user_overrides_path()}) or `mcp-codemode enable --user <server>` (user-wide; required "
        f"for GUI clients launched outside the workspace), or set `{ENABLE_ENV_VAR}` / "
        f"`{DISABLE_ENV_VAR}` before launching the client."
    )
    return [
        {
            "name": "search",
            "description": search_desc,
            "inputSchema": {
                "type": "object",
                "properties": {
                    "code": {
                        "type": "string",
                        "description": "JS/TS snippet or `async () => { ... }` for discovery.",
                    }
                },
                "required": ["code"],
                "additionalProperties": False,
            },
            "annotations": {
                "readOnlyHint": True,
                "destructiveHint": False,
                "idempotentHint": True,
                "openWorldHint": True,
            },
        },
        {
            "name": "execute",
            "description": exec_desc,
            "inputSchema": {
                "type": "object",
                "properties": {
                    "code": {
                        "type": "string",
                        "description": (
                            "JS/TS snippet or `async () => { ... }` calling "
                            "`codemode.<server>.<tool>(args)`."
                        ),
                    }
                },
                "required": ["code"],
                "additionalProperties": False,
            },
            "annotations": {
                "readOnlyHint": False,
                "openWorldHint": True,
            },
        },
    ]


@dataclass(frozen=True)
class _DiscoveryOpts:
    refresh: bool
    compact: bool
    deadline: float
    cancel_event: threading.Event | None = None


class CodeModeServer:
    """JSON-RPC 2.0 stdio MCP server routing search and execute calls."""

    def __init__(
        self,
        manifest: Manifest,
        sandbox_config: SandboxConfig,
        *,
        cwd: Path | None = None,
    ) -> None:
        """Initialize the Code Mode MCP gateway for a client manifest."""
        self.manifest = manifest
        self.sandbox_config = sandbox_config
        self.cwd = cwd
        self.supervisor = UpstreamSupervisor(manifest)
        self._tools = _build_tool_definitions(manifest)
        self._stdout_lock = threading.Lock()
        self._cancel_lock = threading.Lock()
        self._inflight_cancels: set[threading.Event] = set()
        self._active_cancels: dict[str | int | float, list[threading.Event]] = {}

    def _current_states(self) -> tuple[dict[str, bool], dict[str, str]]:
        states, sources = resolve_enabled_servers(self.manifest, self.cwd)
        self.supervisor.close_disabled(states)
        return states, sources

    def _handle_servers_rpc(self) -> list[dict[str, object]]:
        states, sources = self._current_states()
        return [
            {
                "name": spec.name,
                "alias": spec.alias,
                "transport": spec.transport,
                "enabled": states[spec.name],
                "source": sources[spec.name],
                "primaryUse": spec.primary_use,
                "accessNotes": spec.access_notes,
            }
            for spec in self.manifest.servers.values()
        ]

    def _inspect_server_tools(
        self,
        name: str,
        *,
        enabled: bool,
        opts: _DiscoveryOpts,
    ) -> dict[str, object]:
        spec = self.manifest.servers[name]
        if not enabled:
            return {
                "server": spec.name,
                "alias": spec.alias,
                "enabled": False,
                "tools": [],
                "error": str(ToolDispatchError.disabled_server(spec.name)),
            }
        try:
            tools = self.supervisor.get_tools(
                spec.name,
                refresh=opts.refresh,
                deadline=opts.deadline,
                cancel_event=opts.cancel_event,
            )
        except UpstreamError as exc:
            return {
                "server": spec.name,
                "alias": spec.alias,
                "enabled": True,
                "tools": [],
                "error": str(exc),
            }
        rendered = [_compact_tool_entry(t) for t in tools] if opts.compact else tools
        return {
            "server": spec.name,
            "alias": spec.alias,
            "enabled": True,
            "tools": rendered,
        }

    def _discover_servers_parallel(
        self,
        enabled_names: list[str],
        opts: _DiscoveryOpts,
    ) -> dict[str, object]:
        results: dict[str, object] = {}
        results_lock = threading.Lock()
        sem = threading.Semaphore(min(len(enabled_names), MAX_DISCOVERY_WORKERS))

        def _probe(name: str) -> None:
            with sem:
                entry = self._inspect_server_tools(name, enabled=True, opts=opts)
            with results_lock:
                results[name] = entry

        threads: dict[str, threading.Thread] = {}
        for name in enabled_names:
            thread = threading.Thread(target=_probe, args=(name,), daemon=True)
            threads[name] = thread
            thread.start()

        join_deadline = opts.deadline + 0.5
        for thread in threads.values():
            remaining = join_deadline - time.monotonic()
            if remaining > 0:
                thread.join(timeout=remaining)

        out: dict[str, object] = {}
        with results_lock:
            for name in enabled_names:
                if name in results:
                    out[name] = results[name]
                else:
                    spec = self.manifest.servers[name]
                    out[name] = {
                        "server": spec.name,
                        "alias": spec.alias,
                        "enabled": True,
                        "tools": [],
                        "error": (
                            f"upstream '{spec.name}' discovery timed out; "
                            f"pass '{spec.name}' to codemode.tools() to wait for cold startup"
                        ),
                    }
        return out

    def _handle_discovery_rpc(
        self,
        params: dict[str, object],
        *,
        compact: bool,
        deadline: float,
        cancel_event: threading.Event | None,
    ) -> dict[str, object]:
        states, _ = self._current_states()
        refresh = bool(params.get("refresh", False))
        target = params.get("server")
        if isinstance(target, str) and target:
            canonical = self.manifest.resolve_name(target)
            if canonical is None:
                raise ToolDispatchError.unknown_server(target)
            return self._inspect_server_tools(
                canonical,
                enabled=states[canonical],
                opts=_DiscoveryOpts(
                    refresh=refresh,
                    compact=compact,
                    deadline=deadline,
                    cancel_event=cancel_event,
                ),
            )

        out: dict[str, object] = {}
        enabled_names: list[str] = []
        for name, spec in self.manifest.servers.items():
            if states[name]:
                enabled_names.append(name)
            else:
                out[name] = {
                    "server": name,
                    "alias": spec.alias,
                    "enabled": False,
                    "tools": [],
                }
        if not enabled_names:
            return out

        probe_deadline = min(deadline, time.monotonic() + UNFILTERED_DISCOVERY_TIMEOUT_SEC)
        out.update(
            self._discover_servers_parallel(
                enabled_names,
                _DiscoveryOpts(
                    refresh=refresh,
                    compact=compact,
                    deadline=probe_deadline,
                    cancel_event=cancel_event,
                ),
            )
        )
        return out

    def _handle_call_tool_rpc(
        self,
        params: dict[str, object],
        attachments: list[dict[str, object]],
        attachments_lock: threading.Lock,
        deadline: float,
        cancel_event: threading.Event | None,
    ) -> object:
        raw_server = str(params.get("server", ""))
        tool_name = str(params.get("tool", ""))
        arguments = as_dict(params.get("args")) or {}

        if not raw_server or not tool_name:
            raise ToolDispatchError.missing_server_or_tool()

        canonical = self.manifest.resolve_name(raw_server)
        if canonical is None:
            raise ToolDispatchError.unknown_server(raw_server)

        states, _ = self._current_states()
        if not states[canonical]:
            raise ToolDispatchError.disabled_server(canonical)

        result = self.supervisor.call_tool(
            canonical,
            tool_name,
            arguments,
            deadline=deadline,
            cancel_event=cancel_event,
        )
        if cancel_event is not None and cancel_event.is_set():
            raise UpstreamError.cancelled(canonical, tool_name)
        if result.get("isError"):
            raise ToolDispatchError.upstream_tool_error(
                canonical,
                tool_name,
                _extract_error_text(result),
            )
        return _unwrap_upstream_result(result, attachments, attachments_lock)

    def _make_rpc_handler(
        self,
        tool_name: str,
        attachments: list[dict[str, object]],
        attachments_lock: threading.Lock,
    ) -> Callable[[str, dict[str, object], float, threading.Event], object]:
        def rpc_handler(
            method: str,
            params: dict[str, object],
            deadline: float,
            cancel_event: threading.Event,
        ) -> object:
            effective_deadline = _rpc_deadline(deadline)
            if method == "servers":
                return self._handle_servers_rpc()
            if method == "tools":
                return self._handle_discovery_rpc(
                    params,
                    compact=True,
                    deadline=effective_deadline,
                    cancel_event=cancel_event,
                )
            if method == "spec":
                return self._handle_discovery_rpc(
                    params,
                    compact=False,
                    deadline=effective_deadline,
                    cancel_event=cancel_event,
                )
            if method == "call_tool":
                if tool_name != "execute":
                    raise ToolDispatchError.unsupported_method(tool_name, method)
                return self._handle_call_tool_rpc(
                    params,
                    attachments,
                    attachments_lock,
                    effective_deadline,
                    cancel_event,
                )
            raise ToolDispatchError.unsupported_method(tool_name, method)

        return rpc_handler

    def run_tool(
        self,
        tool_name: str,
        arguments: dict[str, object],
        *,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object]:
        """Execute a downstream `search` or `execute` tool call and return an MCP result."""
        if tool_name not in ("search", "execute"):
            return {
                "isError": True,
                "content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}],
            }

        code = arguments.get("code")
        if not isinstance(code, str) or not code.strip():
            return {
                "isError": True,
                "content": [
                    {"type": "text", "text": "Parameter 'code' must be a non-empty string."}
                ],
            }

        attachments: list[dict[str, object]] = []
        attachments_lock = threading.Lock()
        rpc_handler = self._make_rpc_handler(tool_name, attachments, attachments_lock)
        effective_config = replace(
            self.sandbox_config,
            cancel_event=cancel_event,
            on_abort=self.supervisor.cancel_active,
        )

        try:
            outcome = run_sandbox(
                code=code,
                mode=tool_name,
                server_aliases=self.manifest.alias_to_name,
                rpc_handler=rpc_handler,
                config=effective_config,
            )
        except SandboxError as exc:
            return {
                "isError": True,
                "content": [{"type": "text", "text": str(exc)}],
            }
        except Exception as exc:  # noqa: BLE001
            sys.stderr.write(f"mcp-codemode: unexpected error running {tool_name}: {exc}\n")
            sys.stderr.flush()
            return {
                "isError": True,
                "content": [{"type": "text", "text": f"codemode internal error: {exc}"}],
            }

        content: list[dict[str, object]] = [
            {"type": "text", "text": _format_execution_text(outcome.value, outcome.logs)}
        ]
        with attachments_lock:
            content.extend(attachments)
        return {"content": content}

    def _negotiate_protocol_version(self, params: dict[str, object]) -> str:
        requested = params.get("protocolVersion")
        if isinstance(requested, str) and requested in SUPPORTED_PROTOCOL_VERSIONS:
            return requested
        return PROTOCOL_VERSION

    def _dispatch_request(
        self,
        method: str,
        params: dict[str, object],
        *,
        cancel_event: threading.Event | None = None,
    ) -> tuple[dict[str, object] | None, dict[str, object] | None]:
        result: dict[str, object] | None = None
        error: dict[str, object] | None = None
        if method == "initialize":
            result = {
                "protocolVersion": self._negotiate_protocol_version(params),
                "capabilities": {"tools": {}},
                "serverInfo": PACKAGE_INFO,
            }
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": self._tools}
        elif method == "tools/call":
            name = params.get("name")
            args = as_dict(params.get("arguments")) or {}
            if not isinstance(name, str):
                error = {"code": RPC_INVALID_PARAMS, "message": "tools/call missing 'name'"}
            else:
                result = self.run_tool(name, args, cancel_event=cancel_event)
        else:
            error = {"code": RPC_METHOD_NOT_FOUND, "message": f"Method not found: {method}"}
        return result, error

    def _register_cancel(self, msg_id: object, cancel_event: threading.Event) -> None:
        with self._cancel_lock:
            self._inflight_cancels.add(cancel_event)
            if is_valid_rpc_id(msg_id):
                self._active_cancels.setdefault(msg_id, []).append(cancel_event)

    def _unregister_cancel(self, msg_id: object, cancel_event: threading.Event) -> None:
        with self._cancel_lock:
            self._inflight_cancels.discard(cancel_event)
            if is_valid_rpc_id(msg_id):
                bucket = self._active_cancels.get(msg_id)
                if bucket is not None:
                    with contextlib.suppress(ValueError):
                        bucket.remove(cancel_event)
                    if not bucket:
                        self._active_cancels.pop(msg_id, None)

    def _cancel_request(self, request_id: object) -> None:
        if not is_valid_rpc_id(request_id):
            return
        with self._cancel_lock:
            events = list(self._active_cancels.get(request_id, ()))
        for cancel_event in events:
            cancel_event.set()

    def handle_message(
        self,
        msg: dict[str, object],
        *,
        cancel_event: threading.Event | None = None,
    ) -> dict[str, object] | None:
        """Process one JSON-RPC 2.0 request or notification."""
        msg_id = msg.get("id")
        method = msg.get("method")
        params = as_dict(msg.get("params")) or {}

        if not isinstance(method, str) or method == "notifications/initialized":
            return None
        if method == "notifications/cancelled":
            request_id = params.get("requestId")
            if request_id is not None:
                self._cancel_request(request_id)
            return None

        result, error = self._dispatch_request(method, params, cancel_event=cancel_event)
        if msg_id is None:
            return None
        if error is not None:
            return {"jsonrpc": "2.0", "id": msg_id, "error": error}
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    def _write_reply(self, reply: dict[str, object]) -> None:
        line = json.dumps(reply, separators=(",", ":")) + "\n"
        with self._stdout_lock, contextlib.suppress(BrokenPipeError, OSError, ValueError):
            sys.stdout.write(line)
            sys.stdout.flush()

    def _run_message_safe(
        self,
        msg: dict[str, object],
        *,
        cancel_event: threading.Event | None = None,
    ) -> None:
        msg_id = msg.get("id")
        try:
            reply = self.handle_message(msg, cancel_event=cancel_event)
        except Exception as exc:  # noqa: BLE001
            sys.stderr.write(f"mcp-codemode: internal error handling message: {exc}\n")
            sys.stderr.flush()
            reply = (
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {
                        "code": RPC_INTERNAL_ERROR,
                        "message": f"Internal error: {exc}",
                    },
                }
                if msg_id is not None
                else None
            )
        finally:
            if cancel_event is not None:
                self._unregister_cancel(msg_id, cancel_event)
        if reply is not None:
            self._write_reply(reply)

    def _parse_stdin_message(self, raw_line: str) -> dict[str, object] | None:
        stripped = raw_line.strip()
        if not stripped:
            return None
        try:
            parsed: object = json.loads(stripped)
        except json.JSONDecodeError as exc:
            sys.stderr.write(f"mcp-codemode: ignoring invalid JSON on stdin: {exc}\n")
            sys.stderr.flush()
            return None
        return as_dict(parsed)

    def _shutdown_workers(
        self,
        work_queue: queue.Queue[tuple[dict[str, object], threading.Event] | None],
        workers: list[threading.Thread],
    ) -> None:
        with self._cancel_lock:
            events = list(self._inflight_cancels)
            self._inflight_cancels.clear()
            self._active_cancels.clear()
        for ev in events:
            ev.set()
        while True:
            try:
                work_queue.get_nowait()
            except queue.Empty:
                break
        for _ in workers:
            with contextlib.suppress(queue.Full):
                work_queue.put_nowait(None)
        join_deadline = time.monotonic() + SHUTDOWN_JOIN_SEC
        for thread in workers:
            remaining = join_deadline - time.monotonic()
            if remaining > 0:
                thread.join(timeout=remaining)

    def _enqueue_tool_call(
        self,
        msg: dict[str, object],
        work_queue: queue.Queue[tuple[dict[str, object], threading.Event] | None],
    ) -> None:
        cancel_event = threading.Event()
        msg_id = msg.get("id")
        self._register_cancel(msg_id, cancel_event)
        try:
            work_queue.put_nowait((msg, cancel_event))
        except queue.Full:
            self._unregister_cancel(msg_id, cancel_event)
            if msg_id is not None:
                self._write_reply(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "error": {
                            "code": RPC_INTERNAL_ERROR,
                            "message": (
                                f"Too many queued tool calls (limit: {MAX_PENDING_REQUESTS})"
                            ),
                        },
                    }
                )

    def serve_stdio(self) -> int:
        """Run the newline-delimited JSON-RPC loop on stdin/stdout until EOF."""
        shutting_down = False

        def _handle_signal(_signum: int, _frame: object) -> None:
            if not shutting_down:
                raise SystemExit(0)

        previous_sigterm = signal.signal(signal.SIGTERM, _handle_signal)
        previous_sigint = signal.signal(signal.SIGINT, _handle_signal)
        work_queue: queue.Queue[tuple[dict[str, object], threading.Event] | None] = queue.Queue(
            maxsize=MAX_PENDING_REQUESTS
        )

        def _worker() -> None:
            while True:
                item = work_queue.get()
                if item is None:
                    return
                msg, cancel_event = item
                self._run_message_safe(msg, cancel_event=cancel_event)

        workers = [
            threading.Thread(target=_worker, daemon=True) for _ in range(MAX_CONCURRENT_REQUESTS)
        ]
        for thread in workers:
            thread.start()

        try:
            for raw_line in sys.stdin:
                msg = self._parse_stdin_message(raw_line)
                if msg is None:
                    continue
                if msg.get("method") == "tools/call":
                    self._enqueue_tool_call(msg, work_queue)
                else:
                    self._run_message_safe(msg)
        finally:
            shutting_down = True
            try:
                self._shutdown_workers(work_queue, workers)
            finally:
                self.supervisor.close_all()
                signal.signal(signal.SIGTERM, previous_sigterm)
                signal.signal(signal.SIGINT, previous_sigint)
        return 0
