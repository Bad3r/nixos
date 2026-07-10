{
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config;
  predicate = pkg: builtins.elem (lib.getName pkg) cfg.nixpkgs.allowedUnfreePackages;
in
{
  # Unfree entries are declared at the flake-parts level only (any module can
  # contribute to this option); there is deliberately no NixOS-scope or
  # Home Manager-scope allowlist option, the predicate below is shared.
  options.nixpkgs.allowedUnfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  config = {
    perSystem =
      { system, ... }:
      {
        config._module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = cfg.nixpkgs.overlays or [ ];
          config = (cfg.nixpkgs.config or { }) // {
            allowUnfreePredicate = predicate;
          };
        };
      };

    flake = {
      nixosModules.base.nixpkgs.config.allowUnfreePredicate = predicate;

      homeManagerModules.base = args: {
        nixpkgs.config = lib.mkIf (!(args.hasGlobalPkgs or false)) {
          allowUnfreePredicate = predicate;
        };
      };

      lib.meta.nixpkgs.allowedUnfreePackages = cfg.nixpkgs.allowedUnfreePackages;
    };
  };
}
