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


def _noop_rpc(
    _method: str,
    _params: dict[str, object],
    _deadline: float,
    _cancel: threading.Event,
) -> object:
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
        """Assemble Bubblewrap flags including cap-drop and /tmp cap, and reject missing bwrap."""
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
        self.assertIn("--cap-drop", cmd)
        self.assertEqual(cmd[cmd.index("--cap-drop") + 1], "ALL")
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
        """Hide Node globals, strip TS types, marshal VM realms, and dispatch RPC calls."""
        calls: list[tuple[str, dict[str, object]]] = []

        def rpc(
            method: str,
            params: dict[str, object],
            _deadline: float,
            _cancel: threading.Event,
        ) -> object:
            calls.append((method, params))
            if method == "servers":
                return [{"name": "mock-srv", "alias": "mock_srv", "enabled": True}]
            if method == "call_tool":
                if params.get("tool") == "fail":
                    msg = "upstream boom"
                    raise RuntimeError(msg)
                return {
                    "echo": params["args"],
                    "server": params["server"],
                    "tool": params["tool"],
                }
            return None

        code = """
        async () => {
          type Info = { globalsHidden: boolean; tsWorks: number };
          console.log("starting", undefined);
          const globalsHidden =
            typeof process === "undefined" &&
            typeof require === "undefined" &&
            typeof fetch === "undefined";
          const servers = await codemode.servers();
          const serversIsArray = servers instanceof Array;
          const viaAlias = await codemode.mock_srv.ping({ ok: true });
          const viaExact = await codemode["mock-srv"].ping({ ok: 2 });
          const proxyJson = JSON.stringify(codemode.mock_srv);
          let caughtVmError = false;
          try {
            await codemode.mock_srv.fail({});
          } catch (e) {
            caughtVmError = e instanceof Error && e.message.includes("upstream boom");
          }
          let caughtBigInt = false;
          try {
            await codemode.mock_srv.ping({ n: 1n });
          } catch (e) {
            caughtBigInt = e instanceof Error && e.message.includes("serialization");
          }
          const timerId = setTimeout(() => {}, 5000);
          clearTimeout(timerId);
          const info: Info = { globalsHidden, tsWorks: 42 };
          return {
            info,
            serversIsArray,
            viaAlias,
            viaExact,
            proxyJson,
            caughtVmError,
            caughtBigInt,
            timerIsNumber: typeof timerId === "number",
          };
        }
        """
        result = run_sandbox(
            code=code,
            mode="execute",
            server_aliases={"mock_srv": "mock-srv"},
            rpc_handler=rpc,
            config=self._config(),
        )
        self.assertEqual(result.logs, ["starting undefined"])
        value = cast("dict[str, object]", result.value)
        info = cast("dict[str, object]", value["info"])
        via_alias = cast("dict[str, object]", value["viaAlias"])
        via_exact = cast("dict[str, object]", value["viaExact"])
        self.assertTrue(info["globalsHidden"])
        self.assertEqual(info["tsWorks"], 42)
        self.assertTrue(value["serversIsArray"])
        self.assertEqual(via_alias["server"], "mock-srv")
        self.assertEqual(via_exact["server"], "mock-srv")
        self.assertEqual(value["proxyJson"], "{}")
        self.assertTrue(value["caughtVmError"])
        self.assertTrue(value["caughtBigInt"])
        self.assertTrue(value["timerIsNumber"])
        expected_rpc_calls = 4
        self.assertEqual(len(calls), expected_rpc_calls)

    def test_snippet_forms_options_first_arg_and_error_logs(self) -> None:
        """Support bare await, TS prelude + comments, options-only tools(), and error logs."""
        seen: list[tuple[str, dict[str, object]]] = []

        def rpc(
            method: str,
            params: dict[str, object],
            _deadline: float,
            _cancel: threading.Event,
        ) -> object:
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

        expected_nine = 9
        for snippet in (
            "async () => { return 9; }\n// trailing comment",
            "async () => { return 9; };\n// trailing comment after semi",
            "async () => { return 9; }; // inline trailing comment",
            "type Out = number;\nasync (): Promise<Out> => { return 9; };",
            "4 /* left */ + 5 /* right */",
            "async () => { /* keep */ return 9; } /* tail */",
        ):
            res = run_sandbox(
                code=snippet,
                mode="search",
                server_aliases={},
                rpc_handler=rpc,
                config=self._config(),
            )
            self.assertEqual(res.value, expected_nine, snippet)

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

        with self.assertRaises(SandboxError) as null_err_ctx:
            run_sandbox(
                code="async () => { throw Object.create(null); }",
                mode="search",
                server_aliases={},
                rpc_handler=rpc,
                config=self._config(),
            )
        self.assertIn("unprintable error", str(null_err_ctx.exception))

    def test_search_mode_blocks_tool_calls_and_host_tampering(self) -> None:
        """Omit codemode.call in search mode and keep host constructors/prototypes frozen."""
        res = run_sandbox(
            code="async () => typeof codemode.call",
            mode="search",
            server_aliases={},
            rpc_handler=_noop_rpc,
            config=self._config(),
        )
        self.assertEqual(res.value, "undefined")

        tampered = run_sandbox(
            code="""
            async () => {
              const hostObjProto = Object.getPrototypeOf(URL.prototype);
              const hostObjCtor = hostObjProto.constructor;
              const hostMapProto = Object.getPrototypeOf(structuredClone(new Map()));
              const hostStrProto = Object.getPrototypeOf(structuredClone(new String("")));
              try { hostObjProto.toJSON = () => ({ type: "done", value: "pwned" }); } catch {}
              try { hostObjCtor.assign = () => ({ type: "done", value: "pwned" }); } catch {}
              try { hostMapProto.get = () => null; } catch {}
              try { hostStrProto.trim = () => "pwned"; } catch {}
              return {
                objCtorFrozen: Object.isFrozen(hostObjCtor),
                mapProtoFrozen: Object.isFrozen(hostMapProto),
                strProtoFrozen: Object.isFrozen(hostStrProto),
                label: "clean",
              };
            }
            """,
            mode="search",
            server_aliases={},
            rpc_handler=_noop_rpc,
            config=self._config(),
        )
        tampered_dict = cast("dict[str, object]", tampered.value)
        self.assertTrue(tampered_dict["objCtorFrozen"])
        self.assertTrue(tampered_dict["mapProtoFrozen"])
        self.assertTrue(tampered_dict["strProtoFrozen"])
        self.assertEqual(tampered_dict["label"], "clean")

    def test_timeout_cancellation_and_truncation(self) -> None:
        """Enforce wall-clock timeout, pre-set/in-flight cancellation, and text truncation."""
        already_cancelled = threading.Event()
        already_cancelled.set()
        with self.assertRaises(SandboxError) as pre_ctx:
            run_sandbox(
                code="async () => 1",
                mode="search",
                server_aliases={},
                rpc_handler=_noop_rpc,
                config=self._config(cancel_event=already_cancelled),
            )
        self.assertIn("cancelled", str(pre_ctx.exception))

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

        def count_rpc(
            method: str,
            _params: dict[str, object],
            _deadline: float,
            _cancel: threading.Event,
        ) -> object:
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
        """Abort promptly on slow RPC, trigger cancel event, and block Function escape."""
        seen_cancel = threading.Event()

        def slow_rpc(
            _method: str,
            _params: dict[str, object],
            _deadline: float,
            cancel: threading.Event,
        ) -> object:
            if cancel.wait(2.5):
                seen_cancel.set()
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
        self.assertTrue(seen_cancel.wait(1.0))

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
