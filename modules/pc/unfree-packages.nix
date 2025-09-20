{ lib, config, ... }:
{
  options.nixpkgs.allowedUnfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };
  config.flake =
    let
      predicate = pkg: builtins.elem (lib.getName pkg) config.nixpkgs.allowedUnfreePackages;
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
      nixosModules.pc.imports = [ optionModule ];
      nixosModules.base.nixpkgs.config.allowUnfreePredicate = predicate;

      homeManagerModules.base = args: {
        nixpkgs.config = lib.mkIf (!(args.hasGlobalPkgs or false)) {
          allowUnfreePredicate = predicate;
        };
      };

      lib.meta.nixpkgs.allowedUnfreePackages = config.nixpkgs.allowedUnfreePackages;
    };

}
