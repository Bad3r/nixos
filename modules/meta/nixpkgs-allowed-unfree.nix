{
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config;
  predicate = pkg: builtins.elem (lib.getName pkg) cfg.nixpkgs.allowedUnfreePackages;
  optionModule =
    { lib, ... }:
    {
      options.nixpkgs.allowedUnfreePackages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
in
{
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
      nixosModules.base.imports = [ optionModule ];
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
