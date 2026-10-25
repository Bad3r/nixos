{ config, lib, ... }:
let
  inherit (config.flake.lib.agents) scratchDir;
  bash = command: {
    tool_name = "Bash";
    cwd = "/test/path";
    tool_input = { inherit command; };
  };
  patch = path: {
    tool_name = "apply_patch";
    cwd = "/test/path";
    tool_input.command = "*** Begin Patch\n*** Add File: ${path}\n+x\n*** End Patch";
  };
  write = file_path: {
    tool_name = "Write";
    tool_input = { inherit file_path; };
  };
in
{
  flake.lib.agents._internal.hooks.raw.scratch-guard = {
    name = "scratch-guard";
    event = "PreToolUse";
    timeout = 10;
    package =
      pkgs:
      pkgs.writeShellApplication {
        name = "agent-scratch-guard";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
        ];
        text = ''
          scratch=${lib.escapeShellArg scratchDir}
          ${builtins.readFile ./scratch-guard.sh}
        '';
      };

    claude.matcher = "Write|Edit|MultiEdit|NotebookEdit|Bash";
    codex.matcher = "Bash|apply_patch";

    tests = {
      deny = [
        (write "/tmp/a")
        (write "/tmp")
        {
          tool_name = "NotebookEdit";
          tool_input.notebook_path = "/tmp/n.ipynb";
        }
        (patch "/tmp/notes.md")
        (patch "../../tmp/x")
      ]
      ++ map bash [
        "echo hi > /tmp/x"
        "cmd 2>/tmp/err"
        "ls | tee -a /tmp/log"
        "mkdir -p /tmp/work"
        "cd /tmp && make"
        "git clone https://example.invalid/r /tmp/repo"
        "git worktree add /tmp/wt"
        "cp a.txt /tmp/"
        "mv a /tmp/b"
        "curl -sL https://example.invalid -o /tmp/x.tgz"
        "tar -xzf a.tgz -C /tmp/out"
        "unzip a.zip -d /tmp/z"
        "mktemp -p /tmp"
        "mktemp /tmp/foo.XXXX"
        "dd if=/dev/zero of=/tmp/f"
        "export UV_CACHE_DIR=/tmp/uv"
        ''echo x > "/tmp/q"''
        "cat > /tmp/p.diff <<'EOF'\n*** Begin Patch\n*** Add File: a\n+x\n*** End Patch\nEOF"
        "apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: /tmp/a\n+x\n*** End Patch\nEOF"
        "cat > p.diff <<'EOF'\n*** Begin Patch\n*** Add File: a\n+x\n*** End Patch\nEOF\necho x > /tmp/x"
        "sbx cp n:/etc/hosts /tmp/x"
        "sbx cp n:/etc/hosts ../../tmp/"
        "sbx run nixos --out /root/r --to /tmp -- true"
        "sbx run nixos --out /root/r --to=/tmp/out -- true"
        "sbx exec n -- cat /etc/os-release > /tmp/x"
        "sbx exec n -- sh -c 'echo x' > /tmp/x"
        "sbx exec n -- sh -c \"echo $(touch /tmp/x)\""
        "cd /tmp && sbx exec n -- true"
        "sbx exec n -- true | tee /tmp/y"
        "TMPDIR=/tmp sbx run nixos --out /root/r --to \"$TMPDIR\" -- true"
      ];
      allow = [
        (write "${scratchDir}/a")
        (write "/tmp/../home/x")
        (write "/var/tmp/x")
        (patch "src/a.md")
        {
          tool_name = "Read";
          tool_input.file_path = "/tmp/a";
        }
      ]
      ++ map bash [
        "cat /tmp/x"
        "ls -la /tmp"
        "cp /tmp/x ${scratchDir}/"
        "mv /tmp/old ${scratchDir}/old"
        "rsync -a /tmp/src/ ${scratchDir}/src/"
        "grep foo /tmp/log > out.txt"
        "[ -d /tmp/foo ] && echo y"
        "echo hi 2>/dev/null"
        "mktemp -d"
        "ls /tmp/.X11-unix"
        "cd /tmpfoo"
        ''echo x > "$TMPDIR/a"''
        "apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: src/a\n+x\n*** End Patch\nEOF"
        "sbx exec n --json -- sh -c 'app > /tmp/app.log 2>&1 </dev/null &'"
        "sbx exec n -- sh -c 'echo x > /tmp/a'"
        "sbx exec n -- mkdir -p /tmp/work"
        "sbx run nixos --out /tmp/r --to \"$TMPDIR\" -- sh -c 'check > /tmp/r'"
        "sbx cp n:/tmp/a \"$TMPDIR\""
        "sbx cp ${scratchDir}/in n:/tmp/in"
        "sbx run nixos --in /tmp/x -- true"
      ];
    };
  };
}
