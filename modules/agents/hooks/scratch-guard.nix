{ config, lib, ... }:
let
  inherit (config.flake.lib.agents) scratchDir;
  session_id = "0123abcd-0000-4000-8000-000000000000";
  sessionDir = "${scratchDir}/sessions/${session_id}";
  bash = command: {
    tool_name = "Bash";
    cwd = "/test/path";
    inherit session_id;
    tool_input = { inherit command; };
  };
  patch = path: {
    tool_name = "apply_patch";
    cwd = "/test/path";
    inherit session_id;
    tool_input.command = "*** Begin Patch\n*** Add File: ${path}\n+x\n*** End Patch";
  };
  write = file_path: {
    tool_name = "Write";
    inherit session_id;
    tool_input = { inherit file_path; };
  };
  writeContent = file_path: content: {
    tool_name = "Write";
    inherit session_id;
    tool_input = { inherit file_path content; };
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
          scratchRe=${lib.escapeShellArg (lib.escapeRegex scratchDir)}
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
        (write "${scratchDir}/notes.md")
        (patch "${scratchDir}/notes.md")
        (write "${scratchDir}/sessions/a")
        (write "${scratchDir}/sessions/other-session/a")
        (write "${scratchDir}/tmp/a")
        (write "${scratchDir}/sessions-old/../work/a")
        (write "${scratchDir}/sbx-exploration-x_b9mayq/report.md")
        (write "${scratchDir}/0f1e2d3c-4b5a-6789-abcd-ef0123456789/x")
        (write "${scratchDir}/Notes/x")
        (patch "${scratchDir}/catalog-decomp.dPVAZU/x")
        (writeContent "/home/u/.claude/projects/p/memory/x.md" "Report: ${sessionDir}/r.md")
        {
          tool_name = "Edit";
          inherit session_id;
          tool_input = {
            file_path = "/repo/AGENTS.md";
            new_string = "See ${scratchDir}/sessions/abc/plan.md";
          };
        }
        {
          tool_name = "apply_patch";
          inherit session_id;
          tool_input.command = "*** Begin Patch\n*** Update File: /repo/CLAUDE.md\n+see ${sessionDir}/x\n*** End Patch";
        }
        {
          tool_name = "Bash";
          cwd = scratchDir;
          inherit session_id;
          tool_input.command = "sbx cp n:/tmp/a .";
        }
        {
          tool_name = "apply_patch";
          cwd = "/repo";
          inherit session_id;
          tool_input.command = "*** Begin Patch\n*** Update File: AGENTS.md\n+see ${sessionDir}/x\n*** End Patch";
        }
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
        "sbx cp n:/etc/hosts -- /tmp/x"
        "sbx cp n:/etc/hosts ../../tmp/"
        "sbx cp n:/etc/hosts $'/tmp/x'"
        "sbx cp n:/etc/hosts ~/../../tmp/x"
        "sbx cp n:/etc/hosts /tm?/x"
        "sbx run nixos --out /r --to \"$HOME/../../tmp\" -- true"
        "sbx run nixos --out /root/r --to /tmp -- true"
        "sbx run nixos --out /root/r --to=/tmp/out -- true"
        "sbx exec n -- cat /etc/os-release > /tmp/x"
        "sbx exec n -- sh -c 'echo x' > /tmp/x"
        "sbx exec n -- sh -c \"echo $(touch /tmp/x)\""
        "cd /tmp && sbx exec n -- true"
        "sbx exec n -- true | tee /tmp/y"
        "TMPDIR=/tmp sbx run nixos --out /root/r --to \"$TMPDIR\" -- true"
        "echo x > ${scratchDir}/a"
        ''echo x > "${scratchDir}"/a''
        "cmd 2>${scratchDir}/err"
        "ls | tee ${scratchDir}/out.txt"
        "touch ${scratchDir}/a"
        "curl -sL https://example.invalid -o \"${scratchDir}/x.tgz\""
        "cp a.txt ${scratchDir}/"
        "mv a.txt \"${scratchDir}\""
        "sbx cp n:/tmp/a ${scratchDir}"
        "sbx cp n:/tmp/a ${scratchDir}/a"
        "sbx run nixos --out /root/r --to ${scratchDir}/ -- true"
        "mkdir -p ${scratchDir}/work"
        "git clone https://example.invalid/r ${scratchDir}/raindrop-project-cleanup-42i39umo"
        "mkdir ${scratchDir}/pyright-upgrade-pr-600"
        "tar -xf a.tar -C ${scratchDir}"
        "unzip a.zip -d ${scratchDir}/"
        "rsync -a src/ ${scratchDir}/"
        "wget -P ${scratchDir} https://example.invalid/x"
        "nix build .#x --out-link ${scratchDir}/result"
        "tar -xf a.tar -C${scratchDir}"
        "wget -P${scratchDir} https://example.invalid/x"
        "cp -t ${scratchDir} a.txt"
        "curl --output-dir ${scratchDir} -O https://example.invalid/x"
        "rsync -a src/ ${scratchDir}/."
        "sbx cp n:/tmp/a ${scratchDir}/sessions"
        "sbx cp n:/tmp/a ${scratchDir}/sessions/stray"
        "tar -C ${scratchDir} -xf a.tar"
        "tar -f a.tar -x -C ${scratchDir}"
        "tar --zstd -xf a.tar -C ${scratchDir}"
        "mkdir ${scratchDir}/tmp && cd ${scratchDir}/tmp"
      ];
      allow = [
        (write "${scratchDir}/topic/a")
        (patch "${scratchDir}/topic/a")
        (write "${sessionDir}/a")
        (write "${sessionDir}/nested/b")
        (write "${scratchDir}/nixos-pr660/body.md")
        (write "${scratchDir}/sbx-v020/x")
        (write "${scratchDir}/issue-123456/x")
        (writeContent "/home/u/.claude/projects/p/memory/x.md" "Report: ${scratchDir}/virt-plan/r.md")
        (writeContent "${sessionDir}/notes.md" "copy of ${sessionDir}/r.md")
        {
          tool_name = "apply_patch";
          cwd = "/repo";
          inherit session_id;
          tool_input.command = "*** Begin Patch\n*** Update File: AGENTS.md\n-see ${sessionDir}/x\n+see ${scratchDir}/topic/x\n*** End Patch";
        }
        {
          tool_name = "apply_patch";
          cwd = "/repo";
          inherit session_id;
          tool_input.command = "*** Begin Patch\n*** Update File: AGENTS.md\n+see docs\n*** Update File: src/a.sh\n+echo ${sessionDir}/x\n*** End Patch";
        }
        {
          tool_name = "Write";
          tool_input.file_path = "${scratchDir}/topic/a";
        }
        {
          tool_name = "Edit";
          tool_input.file_path = "${scratchDir}/old.md";
        }
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
        "cp /tmp/x ${scratchDir}/topic/"
        "mv /tmp/old ${scratchDir}/old"
        "rsync -a /tmp/src/ ${scratchDir}/src/"
        "grep foo /tmp/log > out.txt"
        "[ -d /tmp/foo ] && echo y"
        "echo hi 2>/dev/null"
        "mktemp -d"
        "ls /tmp/.X11-unix"
        "cd /tmpfoo"
        ''echo x > "$TMPDIR/topic/a"''
        ''echo x > "$TMPDIR"/topic/a''
        "mkdir -p \"$TMPDIR/topic\""
        "echo x > \"$TMPDIR/a\""
        "ls | tee $TMPDIR/out.txt"
        "cp a.txt $TMPDIR/"
        "mkdir -p ${scratchDir}/virt-plan"
        "grep foo ${scratchDir}/claude-1000/x > out.txt"
        "ls -la ${scratchDir}/tmp 2>/dev/null"
        "mkdir -p ${scratchDir}/review-f0a4fac4"
        "git clone https://example.invalid/r ${scratchDir}/pr-123-h264enc"
        "git worktree add ${scratchDir}/test-utf8mb4"
        "echo x > ${sessionDir}/f"
        "tar -xf a.tar -C ${scratchDir}/virt-plan"
        "ls -d ${scratchDir}/*/"
        "ls -d ${scratchDir}/tmp.*"
        "find -P ${scratchDir} -maxdepth 1"
        "tar -czf ~/b.tgz -C ${scratchDir} my-topic"
        "mkdir ${scratchDir}/vm-debian12"
        "mkdir ${scratchDir}/sidebery-gecko157"
        "mkdir -p ${scratchDir}/sbx-ubuntu24"
        "mkdir ${scratchDir}/test-debian13"
        "mkdir ${scratchDir}/kernel-linux612"
        "tar -cf b.tar -C ${scratchDir} my-topic"
        "sbx cp n:/tmp/a \"$TMPDIR\""
        "git clone https://example.invalid/r $TMPDIR/repo"
        "cat $TMPDIR/a > out.txt"
        "curl -sL https://example.invalid -o $TMPDIR/topic/x.tgz"
        "echo x > $TMPDIRX/a"
        "apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: src/a\n+x\n*** End Patch\nEOF"
        "sbx exec n --json -- sh -c 'app > /tmp/app.log 2>&1 </dev/null &'"
        "sbx exec n -- sh -c 'echo x > /tmp/a'"
        "sbx exec n -- mkdir -p /tmp/work"
        "sbx run nixos --out /tmp/r --to \"$TMPDIR/topic\" -- sh -c 'check > /tmp/r'"
        "sbx cp n:/tmp/a \"$TMPDIR/topic\""
        "sbx cp n:/tmp/a \${TMPDIR}/a"
        "sbx cp n:/tmp/a ~/out"
        "sbx cp ${scratchDir}/in n:/tmp/in"
        "sbx run nixos --in /tmp/x -- true"
      ];
    };
  };
}
