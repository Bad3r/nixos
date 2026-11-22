{
  flake.lib.agents._internal.hooks.raw.shell-wrapper-guard =
    let
      bash = command: {
        tool_name = "Bash";
        cwd = "/repo";
        tool_input = { inherit command; };
      };
    in
    {
      name = "shell-wrapper-guard";
      event = "PreToolUse";
      timeout = 10;
      package =
        pkgs:
        pkgs.writeShellApplication {
          name = "agent-shell-wrapper-guard";
          runtimeInputs = [ pkgs.python3 ];
          text = ''
            exec python3 -I ${./shell-wrapper-guard.py}
          '';
        };

      claude.matcher = "Bash";

      tests = {
        deny = map bash [
          "bash -c 'cd /repo && ls'"
          "sh -c 'ls \"$LOCAL_MIRRORS\"'"
          "bash -c \"cd $dir && git status\""
          "cd /repo && bash -c 'git status --short'"
          "cd '/repo' && sh -c 'git diff --stat | tail -3'"
          "cd -- \"$dir\" && bash -c 'ls'"
          "dir=/repo; bash -c \"ls $dir\""
          "bash -c 'git status' 2>&1 | tail -n 5"
          "bash -c 'git status' >/dev/null 2>&1"
          "sh -c 'for t in jq rg; do command -v $t; done'; echo done"
          "# list the tree\nbash -c 'ls'"
          "bash -c 'if [ -L '\\''/a b'\\'' ]; then readlink '\\''/a b'\\''; fi'"
        ];
        allow = [
          {
            tool_name = "Write";
            tool_input.file_path = "/repo/run.sh";
          }
          {
            tool_name = "Bash";
            tool_input = { };
          }
        ]
        ++ map bash [
          "cd /repo && ls"
          "bash script.sh"
          "bash -x script.sh -c release"
          "bash -n -c 'if'"
          "bash -lc 'env | grep OTEL'"
          "bash -ic 'type ll'"
          "bash --login -c env"
          "bash --norc -c 'echo x'"
          "bash -c -i"
          "bash -euc 'make; make test'"
          "bash -e -o pipefail -c 'make | tee log'"
          "bash -c 'echo \"$0\"' 2&>out"
          "bash -c 'pwd' >"
          "zsh -c 'echo $ZSH_VERSION'"
          "/run/current-system/sw/bin/bash -c 'echo x'"
          "LD_PRELOAD=/x/shim.so bash -c 'echo $LD_PRELOAD'"
          "export -p; bash -c 'make; make test'"
          "bash -c 'echo \"$1\"' _ value"
          "bash -c 'echo \"$0\"' '2'>out"
          "bash -c \"$script\""
          "bash -c \"$scr\\\nipt\""
          "bash -c \"\${script:-true}\""
          "bash -c \"\${scripts[0]}\""
          "bash -c \"$(cat fragment.sh)\""
          "bash -c $'source\\t./setup.sh'"
          "bash -c 'source scripts/lib/secrets-guard.sh; secrets_guard_enforce \"$PWD\"'"
          "bash -c 'source</dev/null ./helpers.sh; run'"
          "bash -c '# load helpers\nsource ./helpers.sh; run'"
          "sh -c '. ./_common.sh; guard_port 10100'"
          "'mode=test'; bash -c 'pwd'"
          "bash -c 'echo \"$0\"'{,suffix}"
          "timeout 30 bash -c 'make; make test'"
          "nohup sh -c 'make; make test' &"
          "env -i bash -c env"
          "xargs -I{} sh -c 'echo {}'"
          "find . -name x -exec sh -c 'echo \"$1\"' _ {} \\;"
          "nix develop path:. -c bash -c 'ruff check'"
          "sbx exec n -- sh -c 'echo x > /root/a'"
          "ssh host 'bash -c \"uptime\"'"
          "podman run --rm alpine sh -c 'ls /'"
          "ls -a; bash -c 'make; make test'"
          ">build.log && bash -c 'echo ok'"
          "t() { bash -c \"$1\" 2>&1; }; t 'echo x'"
          "for h in a b; do bash -c \"echo $h\"; done"
          "( bash -c 'echo x' )"
          "x=$(bash -c 'echo hi')"
          "printf '%s\\n' \"$(bash -c 'echo ok')\""
          "args=(bash -c 'echo ok')"
          "value=\${missing:-\\}; bash -c true; }"
          "echo \"run bash -c 'x' to test\""
          "git commit -m 'fix: drop the bash -c wrapper'"
          "rg -n 'sh -c' modules"
          "cat > run.sh <<'EOF'\nbash -c 'echo hi'\nEOF"
          "<<'A B'\nA\nbash -c 'echo ok'\nA B"
          "python3 - <<'PY'\nimport subprocess\nsubprocess.run(['bash', '-c', 'true'])\nPY"
          "ls # bash -c 'x'"
          "$SHELL -c 'echo x'"
          "bash -c 'unterminated"
          "bash"
        ];
      };
    };
}
