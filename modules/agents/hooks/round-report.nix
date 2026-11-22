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
            got=$(stop done)
            echo "$got" | jq -e '.decision == "block"' > /dev/null
            echo "$got" | jq -e '.reason | contains("changed.txt") and contains("ls /nope") and contains("find /nope") and contains("pytest tests")' > /dev/null
            echo "$got" | jq -e '.reason | (contains("rg foo") or contains("grep foo x") or contains("sleep 9") or contains("dirty-before")) | not' > /dev/null
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

            # A session id that leaves the scratch directory is refused.
            jq -nc '{session_id: "../../escape", cwd: "/"}' | hook round-start | jq -e '.systemMessage | startswith("round-report round-start hook failed")' > /dev/null
            [ ! -e "$PWD/escape" ]
            touch "$out"
          '';
    };
}
