{
  lib,
  config,
  inputs,
  ...
}:
let
  nixosConfigs = lib.flip lib.mapAttrs config.configurations.nixos (
    _name:
    { module }:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ module ];
    }
  );
  checksMap = lib.attrValues (
    lib.mapAttrs (name: nixos: {
      ${nixos.config.nixpkgs.hostPlatform.system} = {
        "configurations/nixos/${name}" = nixos.config.system.build.toplevel;
      };
    }) nixosConfigs
  );
in
{
  options.configurations.nixos = lib.mkOption {
    type = lib.types.lazyAttrsOf (
      lib.types.submodule {
        options.module = lib.mkOption {
          type = lib.types.deferredModule;
        };
      }
    );
  };

  config.flake = lib.mkDefault {
    nixosConfigurations = nixosConfigs;
    checks = lib.mkMerge checksMap;
  };
}
