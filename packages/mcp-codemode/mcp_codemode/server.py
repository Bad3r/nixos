# Copyright (c) 2026 Bad3r

"""Downstream MCP JSON-RPC 2.0 server exposing search and execute Code Mode tools."""

from __future__ import annotations

import json
import signal
import sys
from typing import TYPE_CHECKING, cast

from .config import (
    DISABLE_ENV_VAR,
    ENABLE_ENV_VAR,
    Manifest,
    resolve_enabled_servers,
    user_overrides_path,
)
from .sandbox import (
    DEFAULT_EXEC_TIMEOUT_SEC,
    SandboxConfig,
    SandboxError,
    run_sandbox,
    truncate_text,
)
from .upstream import UpstreamError, UpstreamSupervisor

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

PROTOCOL_VERSION = "2025-03-26"
SERVER_INFO = {"name": "mcp-codemode", "version": "0.1.0"}
NON_TEXT_BLOCK_TYPES = frozenset({"image", "audio", "resource", "resource_link"})
RPC_METHOD_NOT_FOUND = -32601
RPC_INVALID_PARAMS = -32602
RPC_INTERNAL_ERROR = -32603


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
            f"`mcp-codemode enable --user {server}` (user-wide), or launch the client with "
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


def _as_dict(value: object) -> dict[str, object] | None:
    if not isinstance(value, dict):
        return None
    raw = cast("dict[object, object]", value)
    return {str(k): v for k, v in raw.items()}


def _as_dict_list(value: object) -> list[dict[str, object]]:
    if not isinstance(value, list):
        return []
    out: list[dict[str, object]] = []
    for item in cast("list[object]", value):
        item_dict = _as_dict(item)
        if item_dict is not None:
            out.append(item_dict)
    return out


def _collect_blocks(
    raw_content: object,
    attachments: list[dict[str, object]],
) -> tuple[list[str], list[dict[str, object]]]:
    text_parts: list[str] = []
    non_text_meta: list[dict[str, object]] = []
    for block in _as_dict_list(raw_content):
        btype = block.get("type")
        if btype == "text":
            text_parts.append(str(block.get("text", "")))
        elif isinstance(btype, str) and btype in NON_TEXT_BLOCK_TYPES:
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
) -> object:
    text_parts, non_text_meta = _collect_blocks(result.get("content"), attachments)
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
        for block in _as_dict_list(result.get("content"))
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
        "Write `async () => { ... }` using `codemode.servers()` "
        "(lists servers, aliases, and enabled/disabled status), "
        "`await codemode.tools(server?, { refresh? })` (compact tool names and descriptions), "
        "and `await codemode.spec(server?, { refresh? })` (full JSON input schemas)."
    )
    exec_desc = (
        "Execute JS/TS in an isolated zero-network, zero-filesystem sandbox with access to "
        "enabled MCP servers via `codemode.<server>.<tool>(args)` or "
        "`codemode.call(server, tool, args)`, plus `codemode.servers()`, `codemode.tools()`, "
        "and `codemode.spec()`. Use `search` first to inspect schemas. Return only the filtered "
        "result you need; output past 24,000 chars is truncated. Toggle opt-in servers without "
        "restarting the client via `mcp-codemode enable <server>` "
        f"(project-scoped in {user_overrides_path()}) or `mcp-codemode enable --user <server>`, "
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
                "openWorldHint": False,
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
        self._alias_map = {spec.alias: spec.name for spec in manifest.servers.values()}
        self._tools = _build_tool_definitions(manifest)

    def _current_states(self) -> tuple[dict[str, bool], dict[str, str]]:
        return resolve_enabled_servers(self.manifest, self.cwd)

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
            tools = self.supervisor.get_tools(spec.name, refresh=refresh)
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
            )

        out: dict[str, object] = {}
        for name, spec in self.manifest.servers.items():
            if states[name]:
                out[name] = self._inspect_server_tools(
                    name,
                    enabled=True,
                    refresh=refresh,
                    compact=compact,
                )
            else:
                out[name] = {
                    "server": name,
                    "alias": spec.alias,
                    "enabled": False,
                    "tools": [],
                }
        return out

    def _handle_call_tool_rpc(
        self,
        params: dict[str, object],
        attachments: list[dict[str, object]],
    ) -> object:
        raw_server = str(params.get("server", ""))
        tool_name = str(params.get("tool", ""))
        arguments = _as_dict(params.get("args")) or {}

        if not raw_server or not tool_name:
            raise ToolDispatchError.missing_server_or_tool()

        canonical = self.manifest.resolve_name(raw_server)
        if canonical is None:
            raise ToolDispatchError.unknown_server(raw_server)

        states, _ = self._current_states()
        if not states[canonical]:
            raise ToolDispatchError.disabled_server(canonical)

        result = self.supervisor.call_tool(canonical, tool_name, arguments)
        if result.get("isError"):
            raise ToolDispatchError.upstream_tool_error(
                canonical,
                tool_name,
                _extract_error_text(result),
            )
        return _unwrap_upstream_result(result, attachments)

    def _make_rpc_handler(
        self,
        tool_name: str,
        attachments: list[dict[str, object]],
    ) -> Callable[[str, dict[str, object]], object]:
        def rpc_handler(method: str, params: dict[str, object]) -> object:
            if method == "servers":
                return self._handle_servers_rpc()
            if method == "tools":
                return self._handle_discovery_rpc(params, compact=True)
            if method == "spec":
                return self._handle_discovery_rpc(params, compact=False)
            if method == "call_tool":
                if tool_name != "execute":
                    raise ToolDispatchError.unsupported_method(tool_name, method)
                return self._handle_call_tool_rpc(params, attachments)
            raise ToolDispatchError.unsupported_method(tool_name, method)

        return rpc_handler

    def run_tool(self, tool_name: str, arguments: dict[str, object]) -> dict[str, object]:
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
        rpc_handler = self._make_rpc_handler(tool_name, attachments)

        try:
            outcome = run_sandbox(
                code=code,
                mode=tool_name,
                server_aliases=self._alias_map,
                rpc_handler=rpc_handler,
                config=self.sandbox_config,
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

    def _dispatch_request(
        self,
        method: str,
        params: dict[str, object],
    ) -> tuple[dict[str, object] | None, dict[str, object] | None]:
        result: dict[str, object] | None = None
        error: dict[str, object] | None = None
        if method == "initialize":
            result = {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": SERVER_INFO,
            }
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": self._tools}
        elif method == "tools/call":
            name = params.get("name")
            args = _as_dict(params.get("arguments")) or {}
            if not isinstance(name, str):
                error = {"code": RPC_INVALID_PARAMS, "message": "tools/call missing 'name'"}
            else:
                result = self.run_tool(name, args)
        else:
            error = {"code": RPC_METHOD_NOT_FOUND, "message": f"Method not found: {method}"}
        return result, error

    def handle_message(self, msg: dict[str, object]) -> dict[str, object] | None:
        """Process one JSON-RPC 2.0 request or notification."""
        msg_id = msg.get("id")
        method = msg.get("method")
        params = _as_dict(msg.get("params")) or {}

        if not isinstance(method, str) or method == "notifications/initialized":
            return None

        result, error = self._dispatch_request(method, params)
        if msg_id is None:
            return None
        if error is not None:
            return {"jsonrpc": "2.0", "id": msg_id, "error": error}
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    def serve_stdio(self) -> int:
        """Run the newline-delimited JSON-RPC loop on stdin/stdout until EOF."""

        def _handle_signal(_signum: int, _frame: object) -> None:
            raise SystemExit(0)

        previous_sigterm = signal.signal(signal.SIGTERM, _handle_signal)
        previous_sigint = signal.signal(signal.SIGINT, _handle_signal)
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
                msg = _as_dict(parsed)
                if msg is None:
                    continue
                try:
                    reply = self.handle_message(msg)
                except Exception as exc:  # noqa: BLE001
                    sys.stderr.write(f"mcp-codemode: internal error handling message: {exc}\n")
                    sys.stderr.flush()
                    msg_id = msg.get("id")
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
                if reply is not None:
                    sys.stdout.write(json.dumps(reply, separators=(",", ":")) + "\n")
                    sys.stdout.flush()
        finally:
            signal.signal(signal.SIGTERM, previous_sigterm)
            signal.signal(signal.SIGINT, previous_sigint)
            self.supervisor.close_all()
        return 0


def build_sandbox_config(
    *,
    node_bin: str,
    bwrap_bin: str | None,
    sandbox_script: Path,
    use_bwrap: bool = True,
    timeout_sec: float = DEFAULT_EXEC_TIMEOUT_SEC,
) -> SandboxConfig:
    """Construct a SandboxConfig from resolved runtime binaries."""
    return SandboxConfig(
        node_bin=node_bin,
        bwrap_bin=bwrap_bin,
        sandbox_script=sandbox_script,
        use_bwrap=use_bwrap,
        timeout_sec=timeout_sec,
    )
