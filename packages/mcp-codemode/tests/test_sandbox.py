# Copyright (c) 2026 Bad3r

"""Tests for the Node 24 VM sandbox runner, RPC bridge, timeout, and truncation."""

from __future__ import annotations

import unittest
from typing import cast

from mcp_codemode._paths import resolve_node_bin, resolve_sandbox_script
from mcp_codemode.sandbox import (
    MAX_TEXT_CHARS,
    SandboxConfig,
    SandboxError,
    run_sandbox,
    truncate_text,
)


class SandboxTest(unittest.TestCase):
    """Covers Node --permission isolation, TS stripping, RPC proxies, and timeouts."""

    def _config(self, *, timeout_sec: float = 15.0) -> SandboxConfig:
        return SandboxConfig(
            node_bin=resolve_node_bin(),
            bwrap_bin=None,
            sandbox_script=resolve_sandbox_script(),
            use_bwrap=False,
            timeout_sec=timeout_sec,
        )

    def test_sandbox_blocks_globals_and_runs_ts_and_rpc(self) -> None:
        """Hide Node globals, strip TS types, and dispatch alias/exact RPC calls."""
        calls: list[tuple[str, dict[str, object]]] = []

        def rpc(method: str, params: dict[str, object]) -> object:
            calls.append((method, params))
            if method == "servers":
                return [{"name": "mock-srv", "alias": "mock_srv", "enabled": True}]
            if method == "call_tool":
                return {
                    "echo": params["args"],
                    "server": params["server"],
                    "tool": params["tool"],
                }
            return None

        code = """
        async () => {
          type Info = { globalsHidden: boolean; tsWorks: number };
          console.log("starting");
          const globalsHidden =
            typeof process === "undefined" &&
            typeof require === "undefined" &&
            typeof fetch === "undefined";
          const servers = await codemode.servers();
          const viaAlias = await codemode.mock_srv.ping({ ok: true });
          const viaExact = await codemode["mock-srv"].ping({ ok: 2 });
          const info: Info = { globalsHidden, tsWorks: 42 };
          return { info, servers, viaAlias, viaExact };
        }
        """
        result = run_sandbox(
            code=code,
            mode="execute",
            server_aliases={"mock_srv": "mock-srv"},
            rpc_handler=rpc,
            config=self._config(),
        )
        self.assertEqual(result.logs, ["starting"])
        value = cast("dict[str, object]", result.value)
        info = cast("dict[str, object]", value["info"])
        via_alias = cast("dict[str, object]", value["viaAlias"])
        via_exact = cast("dict[str, object]", value["viaExact"])
        self.assertTrue(info["globalsHidden"])
        self.assertEqual(info["tsWorks"], 42)
        self.assertEqual(via_alias["server"], "mock-srv")
        self.assertEqual(via_exact["server"], "mock-srv")
        self.assertEqual(len(calls), 3)

    def test_search_mode_blocks_tool_calls_and_errors_surface(self) -> None:
        """Omit codemode.call in search mode and surface thrown JS errors."""

        def rpc(method: str, _params: dict[str, object]) -> object:
            if method == "servers":
                return []
            err_msg = "unexpected"
            raise RuntimeError(err_msg)

        res = run_sandbox(
            code="async () => typeof codemode.call",
            mode="search",
            server_aliases={},
            rpc_handler=rpc,
            config=self._config(),
        )
        self.assertEqual(res.value, "undefined")

        with self.assertRaises(SandboxError) as ctx:
            run_sandbox(
                code='async () => { throw new Error("boom"); }',
                mode="execute",
                server_aliases={},
                rpc_handler=rpc,
                config=self._config(),
            )
        self.assertIn("boom", str(ctx.exception))

    def test_timeout_and_truncation(self) -> None:
        """Enforce wall-clock timeout and truncate output beyond MAX_TEXT_CHARS."""
        with self.assertRaises(SandboxError) as ctx:
            run_sandbox(
                code="async () => new Promise(() => {})",
                mode="search",
                server_aliases={},
                rpc_handler=lambda _m, _p: None,
                config=self._config(timeout_sec=0.3),
            )
        self.assertIn("timed out", str(ctx.exception))

        big = "x" * (MAX_TEXT_CHARS + 50)
        truncated = truncate_text(big)
        self.assertTrue(truncated.endswith("--- TRUNCATED ---"))
        self.assertLess(len(truncated), len(big))
