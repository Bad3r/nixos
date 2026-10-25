# Codex fails open on a PreToolUse "ask" (codex-rs/hooks output_parser.rs),
# and its execpolicy prompts go to the auto reviewer, so Codex gets a deny.
{ lib, ... }:
let
  matcher = "Bash|mcp__sbx__create|mcp__sbx__run";

  bash = command: {
    tool_name = "Bash";
    tool_input = { inherit command; };
  };
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
    "/run/current-system/sw/bin/sbx run nixos --net egress -- true"
    "cd repo && sbx run nixos --net egress -- true"
    "sbx run nixos \\\n  --net egress -- true"
    "bash -lc 'sbx create nixos --net egress'"
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
    "echo shared | xargs sbx share attach n"
    "workloads share attach sbx-n shared"
    "echo '{\"method\":\"tools/call\"}' | sbx-mcp"
    "sbx-mcp < request.json"
    "/run/current-system/sw/bin/sbx-mcp <<< '{}'"
  ];

  offline = [
    (mcp "create" { base = "nixos"; })
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
    "sbx run nixos --in . -- sh -c 'sbx-mcp; sbx create nixos --net egress'"
    "echo n | xargs sbx destroy"
    "bash -c 'sbx list --mine'"
    "sbx share attach n docs"
    "sbx share detach n shared"
    "sbx list --mine"
    "rg -- '--net egress' packages/sbx"
    "docker run --net host alpine"
    "git commit -m 'sbx: read --net egress and share attach n shared'"
    "workloads share attach guest:dev shared"
    "cat <<'EOF'\nit's fine\nEOF"
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
