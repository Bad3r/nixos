{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 AI agents.") config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

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
