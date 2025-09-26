{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role ai-agents)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  aiAgentApps = [
    "claude-code"
    "codex"
    "coderabbit-cli"
    "github-mcp-server"
  ];
  roleImports = getApps aiAgentApps;
in
{
  # Aggregate AI assistant CLIs for hosts that need terminal-first agents.
  flake.nixosModules.roles."ai-agents".imports = roleImports;
}
