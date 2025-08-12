# Module: pc/unfree-packages.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.meta
# Pattern: Metadata configuration - System-wide settings and values

# modules/unfree-packages.nix

{ lib, config, ... }:
{
  options.nixpkgs.allowedUnfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  config.flake.modules =
    let
      predicate = pkg: builtins.elem (lib.getName pkg) config.nixpkgs.allowedUnfreePackages;
    in
    {
      nixos.pc.nixpkgs.config.allowUnfreePredicate = predicate;

      homeManager.base = args: {
        nixpkgs.config = lib.mkIf (!(args.hasGlobalPkgs or false)) {
          allowUnfreePredicate = predicate;
        };
      };
    };
  
  config.flake.meta.nixpkgs.allowedUnfreePackages = config.nixpkgs.allowedUnfreePackages;

}
