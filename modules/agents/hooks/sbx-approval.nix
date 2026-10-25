# Codex fails open on a PreToolUse "ask" (codex-rs/hooks output_parser.rs),
# and its execpolicy prompts go to the auto reviewer, so Codex gets a deny.
_:
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
  ]
  ++ map bash [
    "sbx run nixos --net egress --in . -- curl https://example.invalid"
    "sbx run nixos --in . --net=egress -- true"
    "sbx --json create debian-13 --name d --net egress"
    "sbx create nixos --ne egress"
    "sbx create nixos --net 'egress'"
    "sbx create nixos --net \"$NET\""
    "sbx create nixos --net=$(echo egress)"
    "/run/current-system/sw/bin/sbx run nixos --net egress -- true"
    "cd repo && sbx run nixos --net egress -- true"
    "sbx run nixos \\\n  --net egress -- true"
    "s=sbx; $s run nixos --net egress -- true"
    "sbx share attach n shared"
    "sbx --json share attach n shared"
    "sbx share attach --json n 'shared'"
    "sbx share attach n \"$TAG\""
    "workloads share attach sbx-n shared"
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
    "sbx share attach n docs"
    "sbx share detach n shared"
    "sbx exec n -- ip netns list"
    "sbx list --mine"
    "docker run --net host alpine"
    "workloads share attach guest:dev shared"
  ];

  hook = name: client: decision: {
    inherit name;
    event = "PreToolUse";
    timeout = 10;
    package =
      pkgs:
      pkgs.writeShellApplication {
        name = "agent-${name}";
        runtimeInputs = [
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
        ];
        text = ''
          decision=${decision}
          ${builtins.readFile ./sbx-approval.sh}
        '';
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
