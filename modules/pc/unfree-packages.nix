{ lib, config, ... }:
{
  options.nixpkgs.allowedUnfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };
  config.flake =
    let
      predicate = pkg: builtins.elem (lib.getName pkg) config.nixpkgs.allowedUnfreePackages;
    in
    {
      nixosModules.base.nixpkgs.config.allowUnfreePredicate = predicate;

      homeManagerModules.base = args: {
        nixpkgs.config = lib.mkIf (!(args.hasGlobalPkgs or false)) {
          allowUnfreePredicate = predicate;
        };
      };
    };

  config.flake.lib.meta.nixpkgs.allowedUnfreePackages = config.nixpkgs.allowedUnfreePackages;

}
