# Module: home-manager-infra/checks.nix
# Purpose: Home Manager user environment configuration
# Namespace: flake.modules.perSystem
# Pattern: Per-system configuration - Architecture-specific packages and tools
# Dependencies: config.flake.modules.homeManager,config.flake.modules.homeManager,

{
  config,
  lib,
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks =
        {
          base = with config.flake.modules.homeManager; [ base ];
          gui = with config.flake.modules.homeManager; [
            base
            gui
          ];
        }
        |> lib.mapAttrs' (
          name: modules: {
            name = "home-manager/${name}";
            value =
              {
                inherit pkgs;
                modules = modules ++ [ { home.stateVersion = "25.05"; } ];
              }
              |> inputs.home-manager.lib.homeManagerConfiguration
              |> lib.getAttrFromPath [
                "config"
                "home-files"
              ];
          }
        );
    };
}
