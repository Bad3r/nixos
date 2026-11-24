# Copyright (c) 2026 Bad3r

"""Downstream MCP JSON-RPC 2.0 server exposing search and execute Code Mode tools."""

from __future__ import annotations

import json
import signal
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from typing import TYPE_CHECKING

from ._util import (
    PROTOCOL_VERSION,
    SERVER_INFO,
    SUPPORTED_PROTOCOL_VERSIONS,
    as_dict,
    as_dict_list,
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
RPC_METHOD_NOT_FOUND = -32601
RPC_INVALID_PARAMS = -32602
RPC_INTERNAL_ERROR = -32603
DEFAULT_SEARCH_TIMEOUT_SEC = 60.0
MAX_ATTACHMENTS = 16
MAX_CONCURRENT_REQUESTS = 8
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
            f"`mcp-codemode enable {server}` (project-scoped in {user_overrides_path()}) or "
            f"`mcp-codemode enable --user {server}` (user-wide; required for GUI clients), "
            f"or launch the client with `{ENABLE_ENV_VAR}={server}`."
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
            if "mimeType" in block:
                meta["mimeType"] = block["mimeType"]
            if "uri" in block:
                meta["uri"] = block["uri"]
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
        "enabled MCP servers via `codemode.<server>.<tool>(args)` or "
        "`codemode.call(server, tool, args)`, plus `await codemode.servers()`, "
        "`await codemode.tools()`, and `await codemode.spec()`. Use `search` first to inspect "
        "schemas. Return only the filtered result you need; output past 24,000 chars is "
        "truncated. Toggle opt-in servers without restarting the client via "
        f"`mcp-codemode enable <server>` (project-scoped in {user_overrides_path()}) or "
        "`mcp-codemode enable --user <server>` (user-wide; required for GUI clients), "
        f"or set `{ENABLE_ENV_VAR}` / `{DISABLE_ENV_VAR}` before launching the client."
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
        self._active_cancels: dict[object, threading.Event] = {}

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
        refresh: bool,
        compact: bool,
        deadline: float | None,
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
            tools = self.supervisor.get_tools(spec.name, refresh=refresh, deadline=deadline)
        except UpstreamError as exc:
            return {
                "server": spec.name,
                "alias": spec.alias,
                "enabled": True,
                "tools": [],
                "error": str(exc),
            }
        rendered = [_compact_tool_entry(t) for t in tools] if compact else tools
        return {
            "server": spec.name,
            "alias": spec.alias,
            "enabled": True,
            "tools": rendered,
        }

    def _handle_discovery_rpc(
        self,
        params: dict[str, object],
        *,
        compact: bool,
        deadline: float,
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
                refresh=refresh,
                compact=compact,
                deadline=deadline,
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

        workers = min(len(enabled_names), MAX_DISCOVERY_WORKERS)
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                name: pool.submit(
                    self._inspect_server_tools,
                    name,
                    enabled=True,
                    refresh=refresh,
                    compact=compact,
                    deadline=deadline,
                )
                for name in enabled_names
            }
            for name, fut in futures.items():
                out[name] = fut.result()
        return out

    def _handle_call_tool_rpc(
        self,
        params: dict[str, object],
        attachments: list[dict[str, object]],
        attachments_lock: threading.Lock,
        deadline: float,
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

        result = self.supervisor.call_tool(canonical, tool_name, arguments, deadline=deadline)
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
    ) -> Callable[[str, dict[str, object], float], object]:
        def rpc_handler(method: str, params: dict[str, object], deadline: float) -> object:
            if method == "servers":
                return self._handle_servers_rpc()
            if method == "tools":
                return self._handle_discovery_rpc(params, compact=True, deadline=deadline)
            if method == "spec":
                return self._handle_discovery_rpc(params, compact=False, deadline=deadline)
            if method == "call_tool":
                if tool_name != "execute":
                    raise ToolDispatchError.unsupported_method(tool_name, method)
                return self._handle_call_tool_rpc(params, attachments, attachments_lock, deadline)
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
        effective_timeout = (
            min(self.sandbox_config.timeout_sec, DEFAULT_SEARCH_TIMEOUT_SEC)
            if tool_name == "search"
            else self.sandbox_config.timeout_sec
        )
        effective_config = replace(
            self.sandbox_config,
            timeout_sec=effective_timeout,
            cancel_event=cancel_event,
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
                "serverInfo": SERVER_INFO,
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

    def _cancel_request(self, request_id: object) -> None:
        with self._cancel_lock:
            cancel_event = self._active_cancels.get(request_id)
        if cancel_event is not None:
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
        with self._stdout_lock:
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
            if msg_id is not None and cancel_event is not None:
                with self._cancel_lock:
                    self._active_cancels.pop(msg_id, None)
        if reply is not None:
            self._write_reply(reply)

    def serve_stdio(self) -> int:
        """Run the newline-delimited JSON-RPC loop on stdin/stdout until EOF."""

        def _handle_signal(_signum: int, _frame: object) -> None:
            raise SystemExit(0)

        previous_sigterm = signal.signal(signal.SIGTERM, _handle_signal)
        previous_sigint = signal.signal(signal.SIGINT, _handle_signal)
        executor = ThreadPoolExecutor(max_workers=MAX_CONCURRENT_REQUESTS)
        try:
            for raw_line in sys.stdin:
                stripped = raw_line.strip()
                if not stripped:
                    continue
                try:
                    parsed: object = json.loads(stripped)
                except json.JSONDecodeError as exc:
                    sys.stderr.write(f"mcp-codemode: ignoring invalid JSON on stdin: {exc}\n")
                    sys.stderr.flush()
                    continue
                msg = as_dict(parsed)
                if msg is None:
                    continue
                if msg.get("method") == "tools/call":
                    cancel_event = threading.Event()
                    msg_id = msg.get("id")
                    if msg_id is not None:
                        with self._cancel_lock:
                            self._active_cancels[msg_id] = cancel_event
                    executor.submit(self._run_message_safe, msg, cancel_event=cancel_event)
                else:
                    self._run_message_safe(msg)
        finally:
            with self._cancel_lock:
                for ev in self._active_cancels.values():
                    ev.set()
                self._active_cancels.clear()
            executor.shutdown(wait=True, cancel_futures=True)
            signal.signal(signal.SIGTERM, previous_sigterm)
            signal.signal(signal.SIGINT, previous_sigint)
            self.supervisor.close_all()
        return 0
