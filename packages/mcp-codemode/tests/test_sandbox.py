# Copyright (c) 2026 Bad3r

"""Tests for the Node 24 VM sandbox runner, RPC bridge, timeout, and truncation."""

from __future__ import annotations

import threading
import time
import unittest
from typing import cast

from mcp_codemode._paths import resolve_node_bin, resolve_sandbox_script
from mcp_codemode.sandbox import (
    MAX_TEXT_CHARS,
    SANDBOX_TMPFS_BYTES,
    SandboxConfig,
    SandboxError,
    build_command,
    run_sandbox,
    truncate_text,
)


def _noop_rpc(_method: str, _params: dict[str, object], _deadline: float) -> object:
    return None


class SandboxTest(unittest.TestCase):
    """Covers Node --permission isolation, TS stripping, RPC proxies, bwrap args, and timeouts."""

    def _config(
        self,
        *,
        timeout_sec: float = 15.0,
        cancel_event: threading.Event | None = None,
    ) -> SandboxConfig:
        return SandboxConfig(
            node_bin=resolve_node_bin(),
            bwrap_bin=None,
            sandbox_script=resolve_sandbox_script(),
            use_bwrap=False,
            timeout_sec=timeout_sec,
            cancel_event=cancel_event,
        )

    def test_build_command_with_bwrap_and_missing_bwrap(self) -> None:
        """Assemble Bubblewrap flags including bounded /tmp tmpfs and reject missing bwrap."""
        script = resolve_sandbox_script()
        cmd = build_command(
            SandboxConfig(
                node_bin="/nix/store/node/bin/node",
                bwrap_bin="/nix/store/bwrap/bin/bwrap",
                sandbox_script=script,
                use_bwrap=True,
            )
        )
        self.assertEqual(cmd[0], "/nix/store/bwrap/bin/bwrap")
        self.assertIn("--unshare-all", cmd)
        self.assertIn("--size", cmd)
        size_idx = cmd.index("--size")
        self.assertEqual(cmd[size_idx + 1], str(SANDBOX_TMPFS_BYTES))
        self.assertEqual(cmd[size_idx + 2], "--tmpfs")
        self.assertIn("--disallow-code-generation-from-strings", cmd)

        with self.assertRaises(SandboxError) as ctx:
            build_command(
                SandboxConfig(
                    node_bin="/nix/store/node/bin/node",
                    bwrap_bin=None,
                    sandbox_script=script,
                    use_bwrap=True,
                )
            )
        self.assertIn("bubblewrap", str(ctx.exception))

    def test_sandbox_blocks_globals_and_runs_ts_and_rpc(self) -> None:
        """Hide Node globals, strip TS types, and dispatch alias/exact RPC calls."""
        calls: list[tuple[str, dict[str, object]]] = []

        def rpc(method: str, params: dict[str, object], _deadline: float) -> object:
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

    def test_snippet_forms_options_first_arg_and_error_logs(self) -> None:
        """Support bare await, TS return, trailing comments, options-only tools(), and logs."""
        seen: list[tuple[str, dict[str, object]]] = []

        def rpc(method: str, params: dict[str, object], _deadline: float) -> object:
            seen.append((method, params))
            if method == "servers":
                return ["s1"]
            return {"seen": params}

        bare_await = run_sandbox(
            code="await codemode.servers()",
            mode="search",
            server_aliases={},
            rpc_handler=rpc,
            config=self._config(),
        )
        self.assertEqual(bare_await.value, ["s1"])

        ts_body = run_sandbox(
            code="const n: number = 7; return n * 2;",
            mode="search",
            server_aliases={},
            rpc_handler=rpc,
            config=self._config(),
        )
        expected_double = 14
        self.assertEqual(ts_body.value, expected_double)

        trailing_comment = run_sandbox(
            code="async () => { return 9; }\n// trailing comment",
            mode="search",
            server_aliases={},
            rpc_handler=rpc,
            config=self._config(),
        )
        expected_nine = 9
        self.assertEqual(trailing_comment.value, expected_nine)

        refresh_only = run_sandbox(
            code="await codemode.tools({ refresh: true })",
            mode="search",
            server_aliases={},
            rpc_handler=rpc,
            config=self._config(),
        )
        self.assertEqual(refresh_only.value, {"seen": {"refresh": True}})

        with self.assertRaises(SandboxError) as err_ctx:
            run_sandbox(
                code='async () => { console.log("before-throw"); throw new Error("boom"); }',
                mode="search",
                server_aliases={},
                rpc_handler=rpc,
                config=self._config(),
            )
        self.assertIn("before-throw", str(err_ctx.exception))
        self.assertIn("boom", str(err_ctx.exception))

    def test_search_mode_blocks_tool_calls_and_prototype_pollution(self) -> None:
        """Omit codemode.call in search mode and keep host IPC safe from prototype pollution."""
        res = run_sandbox(
            code="async () => typeof codemode.call",
            mode="search",
            server_aliases={},
            rpc_handler=_noop_rpc,
            config=self._config(),
        )
        self.assertEqual(res.value, "undefined")

        polluted = run_sandbox(
            code="""
            async () => {
              try {
                const proto = Object.getPrototypeOf(URL.prototype);
                proto.toJSON = () => ({ type: "done", value: "pwned" });
              } catch {}
              return "clean";
            }
            """,
            mode="search",
            server_aliases={},
            rpc_handler=_noop_rpc,
            config=self._config(),
        )
        self.assertEqual(polluted.value, "clean")

    def test_timeout_cancellation_and_truncation(self) -> None:
        """Enforce wall-clock timeout, honor cancel_event, and truncate long text."""
        with self.assertRaises(SandboxError) as ctx:
            run_sandbox(
                code="async () => new Promise(() => {})",
                mode="search",
                server_aliases={},
                rpc_handler=_noop_rpc,
                config=self._config(timeout_sec=0.3),
            )
        self.assertIn("timed out", str(ctx.exception))

        cancel = threading.Event()
        threading.Timer(0.15, cancel.set).start()
        t0 = time.monotonic()
        with self.assertRaises(SandboxError) as cancel_ctx:
            run_sandbox(
                code="async () => new Promise(() => {})",
                mode="search",
                server_aliases={},
                rpc_handler=_noop_rpc,
                config=self._config(timeout_sec=10.0, cancel_event=cancel),
            )
        self.assertIn("cancelled", str(cancel_ctx.exception))
        self.assertLess(time.monotonic() - t0, 2.0)

        big = "x" * (MAX_TEXT_CHARS + 50)
        truncated = truncate_text(big)
        self.assertTrue(truncated.endswith("--- TRUNCATED ---"))
        self.assertLess(len(truncated), len(big))

    def test_large_output_not_truncated_by_pipe(self) -> None:
        """Flush stdout before exiting so payloads past 64 KiB survive."""
        expected_len = 200_000
        res = run_sandbox(
            code=f'async () => "x".repeat({expected_len})',
            mode="search",
            server_aliases={},
            rpc_handler=_noop_rpc,
            config=self._config(),
        )
        self.assertEqual(res.value, "x" * expected_len)

    def test_trailing_semicolon_and_no_double_exec_on_error(self) -> None:
        """Execute trailing-semicolon arrows and avoid re-running side effects on errors."""
        res = run_sandbox(
            code="async () => { return 42; };",
            mode="search",
            server_aliases={},
            rpc_handler=_noop_rpc,
            config=self._config(),
        )
        expected_value = 42
        self.assertEqual(res.value, expected_value)

        rpc_calls = 0

        def count_rpc(method: str, _params: dict[str, object], _deadline: float) -> object:
            nonlocal rpc_calls
            rpc_calls += 1
            return {"method": method}

        with self.assertRaises(SandboxError) as ctx:
            run_sandbox(
                code=(
                    "(async () => { await codemode.mock_srv.ping({}); throw new Error('boom'); })()"
                ),
                mode="execute",
                server_aliases={"mock_srv": "mock-srv"},
                rpc_handler=count_rpc,
                config=self._config(),
            )
        self.assertIn("boom", str(ctx.exception))
        self.assertEqual(rpc_calls, 1)

    def test_timeout_during_slow_rpc_is_prompt_and_codegen_blocked(self) -> None:
        """Abort promptly on slow RPC without blocking on sleep, and block Function escape."""

        def slow_rpc(_method: str, _params: dict[str, object], _deadline: float) -> object:
            time.sleep(2.5)
            return {"ok": True}

        t0 = time.monotonic()
        with self.assertRaises(SandboxError) as timeout_ctx:
            run_sandbox(
                code="async () => await codemode.mock_srv.ping({})",
                mode="execute",
                server_aliases={"mock_srv": "mock-srv"},
                rpc_handler=slow_rpc,
                config=self._config(timeout_sec=0.3),
            )
        elapsed = time.monotonic() - t0
        self.assertIn("timed out", str(timeout_ctx.exception))
        self.assertLess(elapsed, 1.8)

        for escape_code in (
            'async () => codemode.servers.constructor.constructor("return 1")()',
            'async () => setTimeout.constructor("return process")()',
        ):
            with self.assertRaises(SandboxError) as esc_ctx:
                run_sandbox(
                    code=escape_code,
                    mode="search",
                    server_aliases={},
                    rpc_handler=_noop_rpc,
                    config=self._config(),
                )
            self.assertIn("disallowed", str(esc_ctx.exception).lower())
