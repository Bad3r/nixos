{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

  aiAgentAppNames = [
    "claude-code"
    "codex"
    "coderabbit-cli"
    "github-mcp-server"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps aiAgentAppNames;
}
