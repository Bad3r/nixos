# Codex fails open on a PreToolUse "ask" (codex-rs/hooks output_parser.rs),
# and its execpolicy prompts go to the auto reviewer, so Codex gets a deny.
{ lib, ... }:
let
  matcher = "Bash|mcp__sbx__create|mcp__sbx__run|mcp__sbx__share_attach";

  bash = command: {
    tool_name = "Bash";
    tool_input = { inherit command; };
  };
  # eval nested n deep around an offline sbx call.
  evals = n: if n == 0 then "sbx list --mine" else "eval ${lib.escapeShellArg (evals (n - 1))}";
  words = n: "echo ${lib.concatStrings (lib.replicate n "x ")}";

  mcp = tool: tool_input: {
    tool_name = "mcp__sbx__${tool}";
    inherit tool_input;
  };

  gated = [
    (mcp "create" {
      base = "nixos";
      net = "egress";
    })
    (mcp "run" {
      base = "nixos";
      net = "egress";
      "in" = [ "/home/u/repo" ];
      command = [ "true" ];
    })
    (mcp "create" "net=egress")
    (mcp "share_attach" {
      name = "n";
      share = "shared";
    })
    (mcp "share_attach" {
      name = "n";
      share = [ "shared" ];
    })
    (mcp "share_attach" { name = "n"; })
    {
      tool_name = "Bash";
      tool_input = "sbx create nixos --net egress";
    }
    {
      tool_name = "Bash";
      tool_input.command = 1;
    }
    (mcp "run" { net = [ "egress" ]; })
    { tool_name = "mcp__sbx__create"; }
    { tool_input.command = "true"; }
    # Malformed JSON, fed verbatim.
    "not json"
    "{\"tool_name\": \"Bash\""
    "[]"
  ]
  ++ map bash [
    "sbx run nixos --net egress --in . -- curl https://example.invalid"
    "sbx run nixos --in . --net=egress -- true"
    "sbx --json create debian-13 --name d --net egress"
    "sbx create nixos --ne egress"
    "sbx create nixos --net 'egress'"
    "sbx create nixos --net \"$NET\""
    "sbx create nixos --net=$(echo egress)"
    "sbx create nixos '--net' egress"
    "sbx create nixos --n\"\"et egress"
    "sbx create nixos --ne\\t egress"
    "sbx create nixos $'--net' egress"
    "sbx create nixos $'\\x2d-net' egress"
    "sbx create nixos {--net,egress}"
    "sbx create nixos $FLAG egress"
    "sbx create nixos --net 'egress"
    "sbx create nixos --ne=egress"
    "sbx create nixos --net="
    "sbx create nixos -$X egress"
    "sbx create nixos --net egress # it's"
    "$'\\x73bx' create nixos --net egress # it's"
    "echo `sbx create nixos --net egress`"
    "sbx create nixos 2>/dev/null --net egress"
    "sbx run nixos </dev/null --net egress -- true"
    "sbx create nixos >out --net egress"
    "sbx create nixos 2>&1 --net egress"
    "sbx create nixos --cpus 2 >log --net egress"
    "sb\\\nx create nixos --net egress"
    "sbx create nixos --name $(echo n) --net egress"
    "sbx create nixos --name <(true) --net egress"
    "sbx create nixos --name `echo n` --net egress"
    "sbx create nixos --name $((1 + 2)) --net egress"
    "sbx create nixos --name \${x:-a b} egress"
    "sbx create nixos --name n\${IFS}--net\${IFS}egress"
    "sbx create nixos --name {x,--net,egress}"
    "sbx create nixos <<<$(echo x) --net egress"
    "{ sbx create nixos --net egress; }"
    "bash <<< 'sbx run nixos --net egress -- true'"
    "echo 'sbx share attach n shared' | sh"
    "cat <<EOF | sh\nsbx create nixos --net egress\nEOF"
    "printf '%s\\n' 'sbx create nixos --net egress' | bash -s"
    ". <(echo sbx create nixos --net egress)"
    "printf 'sbx list' | source /dev/stdin"
    "printf 'sbx list' | bash /dev/stdin"
    "printf 'sbx list' | bash -"
    "printf 'sbx list' | busybox sh"
    "echo 'sbx share attach n shared' | env A=/sh sh"
    "echo 'sbx share attach n shared' | env SHELL=/bin/bash bash"
    "echo 'sbx list' | bash --rcfile /dev/null"
    "echo 'sbx list' | bash --init-file /dev/null"
    "echo 'sbx list' | bash -eo pipefail"
    "echo 'sbx list' | bash -- /dev/stdin"
    "echo 'sbx list' | fish -C 'set x 1'"
    "echo 'sbx list' | bash --frobnicate script.sh"
    "echo 'sbx list' | sudo -u root -g wheel bash"
    "echo 'sbx list' | timeout -k 5 -s KILL 10 bash"
    "printf 'sbx list' | command . /dev/stdin"
    "env -S 'sbx create nixos --net egress'"
    "env --split-string='sbx create nixos --net egress'"
    "env -S'sbx create nixos --net egress'"
    "fish --init-command 'sbx create nixos --net egress'"
    "fish -C 'sbx create nixos --net egress' -c true"
    "# don't\nsbx run nixos --net egress -- true\n# won't"
    "# x\\\nsbx run nixos --net egress -- true"
    "cat <<EOF\nx\nEO\\\nF\nsbx run nixos --net egress -- true"
    "cat <<E\\\nOF\nEOF\nsbx run nixos --net egress -- true"
    "cat <<E\\;\nE;\nsbx run nixos --net egress -- true\nE"
    "cat <<E\\ X\nE X\nsbx run nixos --net egress -- true\nE"
    "cat <<E\\\\F\nEF\ncat <<Z\nE\\F\nsbx run nixos --net egress -- true\nZ"
    "cat <<\"E\\\"F\"\nE\"F\nsbx run nixos --net egress -- true\nE"
    "cat <<\"E\\\"F\\\"G\"\nE\"F\"G\nsbx run nixos --net egress -- true\nEFG"
    "cat <<\"E\\\nOF\"\nEOF\nsbx run nixos --net egress -- true\nE"
    "cat <<$'E\\x41'\nEA\nsbx run nixos --net egress -- true\nE"
    "cat <<$\"E\"\nE\nsbx run nixos --net egress -- true\n$E"
    "echo $(true)#$(sbx run nixos --net egress -- true)"
    "echo \\ #$(sbx run nixos --net egress -- true)"
    "echo \\;#$(sbx run nixos --net egress -- true)"
    "echo \\|#$(sbx run nixos --net egress -- true)"
    "# $'\\n' x\nsbx run nixos --net egress -- true\n# '"
    "bash -c '-x; sbx run nixos --net egress -- true'"
    "bash -c '+x; sbx run nixos --net egress -- true'"
    "env -S '-x; sbx run nixos --net egress -- true'"
    "fish -C '-x; sbx run nixos --net egress -- true'"
    "# say \"hi\nsbx run nixos --net egress -- true\n# bye\""
    "# see $(date\nsbx run nixos --net egress -- true"
    "cat <<EOF\n# don't $(sbx create nixos --net egress)\nEOF"
    "echo 'sbx list' | bash //dev/stdin"
    "echo 'sbx list' | bash /dev/./stdin"
    "echo 'sbx list' | bash /dev/fd//0"
    "echo 'sbx list' | bash /proc/thread-self/fd/0"
    "echo 'sbx list' | bash /proc/123/fd/0"
    "echo 'sbx list' | bash ../../../../dev/stdin"
    "echo 'sbx list' | source /proc/self/fd/0"
    "echo 'sbx list' | . -- /dev/stdin"
    "echo 'sbx list' | bash -- //dev/stdin"
    "env -vS'sbx create nixos --net egress'"
    "fish --init-command='sbx create nixos --net egress'"
    "env A=/sbx sbx share attach n shared"
    "env -C /tmp/sbx sbx share attach n shared"
    "X=/sbx sbx create nixos --name {x,--net,egress}"
    "env -u X sbx create nixos --net egress"
    "sudo -E env PATH=/x/sbx sbx run nixos --net egress -- true"
    "sbx list ${lib.concatStrings (lib.replicate 17 "sbx ")}"
    # Guest argv naming sbx prompts too, since an earlier sbx word may be a mere argument.
    "sbx run nixos --in . -- sh -c 'sbx-mcp; sbx create nixos --net egress'"
    "echo \"$(sbx run nixos --net egress -- true)\""
    "echo \"`sbx share attach n shared`\""
    "x=\"$(sbx run nixos --net egress -- curl https://example.invalid)\""
    "export x=$(sbx run nixos --net egress -- true)"
    "\"$(echo \"$(sbx create nixos --net egress)\")\""
    "cat <(sbx create nixos --net egress)"
    "cat <<EOF\n$(sbx run nixos --net egress -- true)\nEOF"
    "cat <<-EOF\n\t`sbx share attach n shared`\n\tEOF\necho done"
    "bash <<'EOF'\nsbx create nixos --net egress\nEOF"
    "echo \"$(sbx create nixos --net egress\""
    "/run/current-system/sw/bin/sbx run nixos --net egress -- true"
    "cd repo && sbx run nixos --net egress -- true"
    "sbx run nixos \\\n  --net egress -- true"
    "bash -lc 'sbx create nixos --net egress'"
    "bash -ce 'sbx create nixos --net egress'"
    "bash -cl 'sbx create nixos --net egress'"
    "bash -c -- 'sbx create nixos --net egress'"
    "bash -c -o pipefail 'sbx create nixos --net egress'"
    (evals 5)
    (words 33000)
    "bash -c 's\"\"bx create nixos --net egress'"
    "command eval 'sbx create nixos --net egress'"
    "echo nixos | xargs -I{} sh -c 'sbx create {} --net egress'"
    "find . -maxdepth 0 -exec sbx create nixos --net egress \\;"
    "echo egress | xargs sbx create nixos --net"
    "echo --net egress | xargs sbx create nixos"
    "echo create nixos --net egress | xargs sbx"
    "echo share attach n shared | xargs sbx"
    "echo attach n shared | xargs sbx share"
    "sbx share attach n shared"
    "sbx --json share attach n shared"
    "sbx share attach --json n 'shared'"
    "sbx share 'attach' n shared"
    "sbx share attach n shar\\ed"
    "sbx share attach n \"$TAG\""
    "sbx share attach n -- shared"
    "sbx share attach n sha\\\nred"
    "sbx share attach n 2>/dev/null shared"
    "sbx share attach n $(true) shared"
    "echo n | xargs sbx share attach n 2>/dev/null"
    "echo shared | xargs sbx share attach n"
    "workloads share attach sbx-n shared"
    "echo '{\"method\":\"tools/call\"}' | sbx-mcp"
    "sbx-mcp < request.json"
    "/run/current-system/sw/bin/sbx-mcp <<< '{}'"
  ];

  offline = [
    (mcp "create" { base = "nixos"; })
    (mcp "share_attach" {
      name = "n";
      share = "docs";
    })
    (mcp "run" {
      base = "nixos";
      net = "none";
      command = [ "true" ];
    })
    (mcp "exec" {
      name = "n";
      command = [
        "curl"
        "--net"
        "egress"
      ];
    })
    {
      tool_name = "Write";
      tool_input.file_path = "/home/u/sbx-net-egress";
    }
  ]
  ++ map bash [
    "sbx run nixos --in . -- true"
    "sbx run nixos --net none -- true"
    "sbx create nixos --net=none --name n"
    "sbx --json create nixos --gui"
    "sbx run nixos --out /root/r --to \"$TMPDIR\" -- true"
    "sbx run nixos --in . -- sh -c 'curl --net egress'"
    "sbx exec n -- podman run --net=host alpine"
    "sbx exec \"$N\" -- true"
    "echo n | xargs sbx destroy"
    "bash -c 'sbx list --mine'"
    "sbx create nixos 2>/dev/null"
    "sbx run nixos --in . 2>&1 -- true | tee log"
    "sbx exec n -- true > out.txt"
    "sbx exec n -- echo $(date)"
    "sbx create nixos --name \"$(echo n)\""
    "sbx create nixos <<< \"a b\""
    "sbx run nixos --in \"$TMPDIR/dl/tool\" --to \"$TMPDIR\" --out /root/r -- sh -c 'tool > r'"
    "for n in $(sbx list --json | jq -r '.[].name'); do sbx info $n; done"
    "x=\"$(sbx list --json)\""
    "cat <<'EOF'\n$(sbx run nixos --net egress)\nEOF"
    "echo \"$(date)\""
    "echo '$(sbx create nixos --net egress)'"
    "cat <<< \"$(date)\""
    "echo $((1 << 2))"
    "echo \"$(date\""
    "env A=/sbx sbx list"
    "echo hi | sh"
    "bash <<< 'echo hi'"
    "bash script.sh"
    "sh -c 'sbx list'"
    "bash <<< 'sbx list'"
    "source ./env.sh && sbx list"
    "bash --norc -c 'sbx list'"
    "bash --rcfile ~/.bashrc script.sh && sbx list"
    "bash -eo pipefail script.sh && sbx list"
    "sudo -u root sbx list"
    "env -C /tmp sbx list"
    "timeout -s KILL 5 sbx list"
    "rg -S sbx docs"
    "sbx list # don't worry"
    "echo a#b && sbx list"
    "echo a \\\n# b\nsbx list"
    "bash -c -e -- 'sbx list'"
    "echo \${#x} 'a # b' && sbx list"
    "# it's offline\nsbx run nixos -- true"
    "git commit -S -m 'sbx share attach n shared'"
    "git commit -m'sbx: share attach n shared'"
    "git -C ~/x commit -m 'sbx create nixos --net egress'"
    "sort -S 1G sbx.txt"
    "bash ./scripts/run.sh && sbx list"
    "ls /nix/store/*-sbx"
    "git add packages/sbx docs/apps/sbx"
    (evals 4)
    (words 30000)
    "sbx share attach n docs"
    "sbx share detach n shared"
    "sbx list --mine"
    "rg -- '--net egress' packages/sbx"
    "docker run --net host alpine"
    "git commit -m 'sbx: read --net egress and share attach n shared'"
    "workloads share attach guest:dev shared"
    "cat <<'EOF'\nit's fine\nEOF"
    "cat << \\\n EOF\nsbx run nixos --net egress -- true\nEOF"
    "cat <<\"E\\\\F\"\nsbx run nixos --net egress -- true\nE\\F"
  ];

  hook = name: client: decision: {
    inherit name;
    event = "PreToolUse";
    timeout = 10;
    package =
      pkgs:
      pkgs.writeShellApplication {
        name = "agent-${name}";
        text = "exec ${lib.getExe pkgs.python3} -I ${./sbx-approval.py} ${decision}";
      };
    ${client}.matcher = matcher;
    tests = {
      ${decision} = gated;
      allow = offline;
    };
  };
in
{
  flake.lib.agents._internal.hooks.raw = {
    sbx-approval = hook "sbx-approval" "claude" "ask";
    sbx-approval-codex = hook "sbx-approval-codex" "codex" "deny";
  };
}
