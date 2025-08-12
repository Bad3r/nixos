# Module: home/base/shells/nix-index.nix
# Purpose: Nix Index configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment
# Dependencies: inputs.nix-index-database.hmModules.nix-index ,

{ inputs, ... }:
{
  flake.modules.homeManager.base = {
    imports = [ inputs.nix-index-database.hmModules.nix-index ];
    programs = {
      nix-index.enable = true;
      nix-index-database.comma.enable = true;
    };
  };
}
