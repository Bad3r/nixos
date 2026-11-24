# Round report: Claude logs every failed tool call (PostToolUseFailure); both
# harnesses snapshot the git tree when a prompt arrives and, when the agent
# stops, show the files changed and calls failed that round and send the
# agent back once to name each file, account for each failure, and quote its
# test results. Codex's PostToolUse carries no exit code, so its rounds
# report files only. State lives under the session's scratch directory.
{ config, lib, ... }:
let
  inherit (config.flake.lib.agents) scratchDir;

  script =
    pkgs: command:
    pkgs.writeShellApplication {
      name = "agent-round-report-${command}";
      runtimeInputs = [
        pkgs.git
        pkgs.python3
      ];
      text = ''
        export ROUND_REPORT_SCRATCH=${lib.escapeShellArg scratchDir}
        exec python3 -I ${./round-report.py} ${command}
      '';
    };
in
{
  flake.lib.agents._internal.hooks.raw = {
    round-report-failures = {
      name = "round-report-failures";
      event = "PostToolUseFailure";
      timeout = 10;
      package = pkgs: script pkgs "log-failure";
      claude = { };
    };

    round-report-start = {
      name = "round-report-start";
      event = "UserPromptSubmit";
      timeout = 30;
      package = pkgs: script pkgs "round-start";
      claude = { };
      codex = { };
    };

    round-report = {
      name = "round-report";
      event = "Stop";
      timeout = 30;
      package = pkgs: script pkgs "round-end";
      claude = { };
      codex = { };
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      checks."agents/hooks/round-report" =
        pkgs.runCommandLocal "agent-hook-round-report-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = [
              pkgs.git
              pkgs.jq
              pkgs.python3
            ];
          }
          ''
            set -euo pipefail
            export ROUND_REPORT_SCRATCH=$PWD/scratch HOME=$PWD/home
            unset CODEX_HOME
            hook() { python3 -I ${./round-report.py} "$@"; }
            repo=$PWD/repo
            commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -q "$@"; }
            git init -q "$repo"
            echo tracked > "$repo/old.txt"
            git -C "$repo" add old.txt
            commit -m init
            echo keep > "$repo/dirty-before.txt"
            payload() { jq -nc --arg cwd "$repo" "{session_id: \"s\", cwd: \$cwd} + $1"; }
            stop() { local extra="''${3:-}"; payload "{last_assistant_message: \"$1\", stop_hook_active: ''${2:-false}} + ''${extra:-{\}}" | hook round-end; }
            fail() { payload "{tool_name: \"Bash\", tool_input: {command: \"$1\"}, error: \"Exit code $2\\nerr\"}" | hook log-failure; }

            # Changed files and real failures block; benign exits, interrupts and
            # files dirty before the round do not count.
            payload '{}' | hook round-start
            echo new > "$repo/changed.txt"
            fail 'ls /nope' 2
            fail 'find /nope -name x' 1
            fail 'rg foo src' 1
            fail 'grep foo x 2>&1' 1
            fail 'grep -n foo x\npytest tests' 1
            payload '{tool_name: "Bash", tool_input: {command: "sleep 9"}, error: "Interrupted", is_interrupt: true}' | hook log-failure
            payload '{tool_name: "Bash", agent_id: "o1", agent_type: "guardrails-observer", tool_input: {command: "ls /observer-miss"}, error: "Exit code 2\nerr"}' | hook log-failure
            payload '{tool_name: "Bash", agent_id: "a1", agent_type: "Explore", tool_input: {command: "ls /subagent-miss"}, error: "Exit code 2\nerr"}' | hook log-failure
            got=$(stop done)
            echo "$got" | jq -e '.decision == "block"' > /dev/null
            echo "$got" | jq -e '.reason | contains("changed.txt") and contains("ls /nope") and contains("find /nope") and contains("pytest tests") and contains("Explore Bash: ls /subagent-miss")' > /dev/null
            echo "$got" | jq -e '.reason | (contains("rg foo") or contains("grep foo x") or contains("sleep 9") or contains("observer-miss") or contains("dirty-before")) | not' > /dev/null
            echo "$got" | jq -e '.systemMessage | contains("changed.txt") and contains("ls /nope")' > /dev/null

            # Failures are reported once; a summary naming every file passes.
            got=$(stop 'Changed changed.txt')
            echo "$got" | jq -e 'has("decision") | not' > /dev/null

            # A stop that follows a block never blocks, and still shows failures.
            payload '{tool_name: "Read", tool_input: {file_path: "/x"}, error: "File does not exist."}' | hook log-failure
            got=$(stop done true)
            echo "$got" | jq -e '(has("decision") | not) and (.systemMessage | contains("Read"))' > /dev/null

            # Edits to a file already dirty, renames and commits are all listed.
            payload '{}' | hook round-start
            echo more >> "$repo/dirty-before.txt"
            git -C "$repo" mv old.txt renamed.txt
            echo c > "$repo/committed.txt"
            git -C "$repo" add committed.txt
            commit -m c
            got=$(stop done)
            echo "$got" | jq -e '.reason | contains("dirty-before.txt") and contains("old.txt") and contains("renamed.txt") and contains("committed.txt")' > /dev/null
            stop done true > /dev/null

            # A subagent prompt from elsewhere keeps the main round's snapshot.
            payload '{}' | hook round-start
            echo sub > "$repo/main-change.txt"
            jq -nc '{session_id: "s", cwd: "/", agent_id: "a1"}' | hook round-start
            stop done | jq -e '.reason | contains("main-change.txt")' > /dev/null
            stop done true > /dev/null

            # A file too large to hash still shows as changed.
            head -c 2097152 /dev/zero > "$repo/big.bin"
            payload '{}' | hook round-start
            echo more >> "$repo/big.bin"
            stop done | jq -e '.reason | contains("big.bin")' > /dev/null
            stop done true > /dev/null

            # A large untracked directory collapses early without hiding small untracked dirs or later files.
            mkdir -p "$repo/aaa-untracked" "$repo/small-untracked"
            python3 -c '
            from pathlib import Path
            import sys
            root = Path(sys.argv[1])
            for i in range(205):
                (root / f"f{i:03d}.txt").write_text("x\n", encoding="utf-8")
            ' "$repo/aaa-untracked"
            payload '{}' | hook round-start
            jq -e '.starts.main.files["aaa-untracked/"] == "tree:>200"' "$ROUND_REPORT_SCRATCH/sessions/s/hooks/round-report/state.json" > /dev/null
            jq -e '.starts.main.files | has("aaa-untracked/f000.txt") | not' "$ROUND_REPORT_SCRATCH/sessions/s/hooks/round-report/state.json" > /dev/null
            echo real > "$repo/zzz-real.txt"
            echo sub > "$repo/small-untracked/new.txt"
            got=$(stop done)
            echo "$got" | jq -e '.reason | contains("zzz-real.txt") and contains("small-untracked/new.txt") and (contains("aaa-untracked") | not)' > /dev/null
            stop done true > /dev/null
            rm -rf "$repo/aaa-untracked" "$repo/small-untracked" "$repo/zzz-real.txt"

            # Ignored files inside an untracked directory never count.
            printf '__pycache__/\n' > "$repo/.git/info/exclude"
            mkdir -p "$repo/tools"
            echo x > "$repo/tools/run.py"
            payload '{}' | hook round-start
            mkdir -p "$repo/tools/__pycache__"
            echo b > "$repo/tools/__pycache__/run.pyc"
            [ -z "$(stop done)" ]
            rm -rf "$repo/tools"

            # Untracked files the cap window drops or shifts past at round end are not reported.
            for i in $(seq 100 699); do : > "$repo/u$i"; done
            payload '{}' | hook round-start
            echo new > "$repo/a0new"
            stop done | jq -e '.systemMessage | contains("Files changed this round (1)") and contains("a0new")' > /dev/null
            stop done true > /dev/null
            rm -f "$repo/a0new"
            payload '{}' | hook round-start
            rm "$repo/u100"
            got=$(stop done)
            echo "$got" | jq -e '.systemMessage | contains("Files changed this round (1)") and contains("u100")' > /dev/null
            echo "$got" | jq -e '.reason | contains("u100") and (contains("u600") | not)' > /dev/null
            stop done true > /dev/null
            rm -f "$repo"/u*

            # A collapsed untracked directory pushed past UNTRACKED_CAP is not flagged, while deleting it is.
            python3 -c '
            from pathlib import Path
            import sys
            repo = Path(sys.argv[1])
            for i in range(490):
                (repo / f"u{i:03d}").write_text("", encoding="utf-8")
            big = repo / "zzz-big"
            big.mkdir()
            for i in range(205):
                (big / f"f{i:03d}.txt").write_text("x\n", encoding="utf-8")
            ' "$repo"
            payload '{}' | hook round-start
            jq -e '.starts.main.files["zzz-big/"] == "tree:>200"' "$ROUND_REPORT_SCRATCH/sessions/s/hooks/round-report/state.json" > /dev/null
            for i in $(seq -w 0 9); do echo new > "$repo/a${"$"}{i}new"; done
            got=$(stop 'Created a0new a1new a2new a3new a4new a5new a6new a7new a8new a9new.')
            echo "$got" | jq -e '(has("decision") | not) and (.systemMessage | contains("Files changed this round (10)") and contains("a0new") and (contains("zzz-big") | not))' > /dev/null
            rm -f "$repo"/a*new
            payload '{}' | hook round-start
            rm -rf "$repo/zzz-big"
            got=$(stop done)
            echo "$got" | jq -e '.decision == "block" and (.reason | contains("zzz-big/"))' > /dev/null
            stop done true > /dev/null
            rm -f "$repo"/u*

            # A stalled git ls-files scan in untracked_members times out cleanly.
            stub_bin=$PWD/stub-bin
            mkdir -p "$stub_bin"
            real_git=$(command -v git)
            cat > "$stub_bin/git" <<EOF
            #!${pkgs.runtimeShell}
            for arg in "\$@"; do
              if [ "\$arg" = "ls-files" ]; then
                exec sleep 30
              fi
            done
            exec "$real_git" "\$@"
            EOF
            chmod +x "$stub_bin/git"
            PATH="$stub_bin:$PATH" python3 -c '
            import importlib.util, sys, time
            from pathlib import Path
            spec = importlib.util.spec_from_file_location("round_report", "${./round-report.py}")
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            mod.GIT_TIMEOUT_S = 0.2
            started = time.monotonic()
            assert mod.untracked_members(Path(sys.argv[1]), "slow/") is None
            assert time.monotonic() - started < 2.0
            ' "$repo"

            # Staging an already-modified file is detected; interrupted failures do
            # not carry over to the next round; substring paths do not satisfy short names;
            # ./, ~/, repo-rooted absolute, and file:// paths satisfy them, while mismatched prefixes do not.
            echo stage-me > "$repo/app.py"
            mkdir -p "$repo/tests"
            echo test > "$repo/tests/test_app.py"
            git -C "$repo" add app.py tests/test_app.py
            commit -m add-app
            echo edit >> "$repo/app.py"
            fail 'interrupted-prev-round' 2
            payload '{}' | hook round-start
            git -C "$repo" add app.py
            echo edit2 >> "$repo/tests/test_app.py"
            got=$(stop 'Updated tests/test_app.py.')
            echo "$got" | jq -e '.decision == "block"' > /dev/null
            echo "$got" | jq -e '.reason | contains("app.py") and (contains("tests/test_app.py") | not) and (contains("interrupted-prev-round") | not)' > /dev/null
            HOME=$PWD stop "Updated ~/other/app.py and /other$repo/app.py and ./tests/test_app.py." | jq -e '.decision == "block" and (.reason | split("\n") | index("    app.py") and (index("    tests/test_app.py") | not))' > /dev/null
            stop "Updated $repo/app.py:12." | jq -e '.decision == "block" and (.reason | split("\n") | index("    tests/test_app.py") and (index("    app.py") | not))' > /dev/null
            HOME=$PWD stop "Updated ~/repo/app.py:12 and [test_app.py](file://$repo/tests/test_app.py#L1)." | jq -e 'has("decision") | not' > /dev/null

            # Codex rounds are keyed by turn; a stop from another turn sees no snapshot.
            payload '{turn_id: "t1"}' | hook round-start
            echo turn > "$repo/turn.txt"
            [ -z "$(stop done false '{turn_id: "t2"}')" ]
            stop done false '{turn_id: "t1"}' | jq -e '.reason | contains("turn.txt")' > /dev/null

            # Nothing runs inside CODEX_HOME (Codex memory consolidation).
            CODEX_HOME=$repo
            export CODEX_HOME
            payload '{}' | hook round-start
            echo mem > "$repo/memory.md"
            [ -z "$(stop done)" ]
            unset CODEX_HOME

            # Outside a repository with nothing failed, the hook stays silent.
            jq -nc '{session_id: "t", cwd: "/"}' | hook round-start
            [ -z "$(jq -nc '{session_id: "t", cwd: "/", stop_hook_active: false}' | hook round-end)" ]

            # A malformed payload reports the hook's own failure instead of raising.
            echo '[]' | hook round-end | jq -e '.systemMessage | startswith("round-report round-end hook failed")' > /dev/null

            # A session id that is not a single path segment inside sessions/ is refused.
            for bad in "../../escape" "." "../sessions/victim" "a/b"; do
              jq -nc --arg s "$bad" '{session_id: $s, cwd: "/"}' | hook round-start | jq -e '.systemMessage | startswith("round-report round-start hook failed")' > /dev/null
            done
            [ ! -e "$PWD/escape" ]
            [ ! -e "$ROUND_REPORT_SCRATCH/sessions/hooks" ]
            [ ! -e "$ROUND_REPORT_SCRATCH/sessions/victim" ]

            # Non-UTF-8 filenames do not break snapshots, nested-repo hashing, or JSON output.
            bad_name=$(printf 'bad\xff')
            touch "$repo/$bad_name"
            mkdir -p "$repo/nested-bad"
            git init -q "$repo/nested-bad"
            touch "$repo/nested-bad/$bad_name"
            start_out=$(payload '{}' | hook round-start)
            [ -z "$start_out" ]
            [ -z "$(stop done)" ]
            payload '{}' | hook round-start
            echo changed >> "$repo/$bad_name"
            got=$(stop done)
            echo "$got" | jq -e '.decision == "block" and (.systemMessage | startswith("Round report")) and (.systemMessage | contains("bad"))' > /dev/null
            python3 -c 'import json, sys; raw = sys.stdin.read(); assert "\\udc" not in raw.lower(); json.loads(raw)' <<< "$got"
            stop done true > /dev/null
            rm -rf "$repo/$bad_name" "$repo/nested-bad"

            # repo_path refuses paths that escape the repository root.
            python3 -c '
            import importlib.util, sys
            from pathlib import Path
            spec = importlib.util.spec_from_file_location("round_report", "${./round-report.py}")
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            top = Path(sys.argv[1])
            assert mod.repo_path(top, "a/b.txt") == top / "a/b.txt"
            for bad in ("../escape", "/etc/passwd", "."):
                try:
                    mod.repo_path(top, bad)
                except ValueError:
                    pass
                else:
                    raise AssertionError(f"accepted {bad!r}")
            ' "$repo"
            touch "$out"
          '';
    };
}
