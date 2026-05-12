{
  lib,
  config,
  inputs,
  secretsRoot,
  metaOwner,
  ...
}:
let
  nixosConfigs = lib.flip lib.mapAttrs config.configurations.nixos (
    name:
    { module }:
    let
      hostName = name;
      shareCommon = lib.attrByPath [ hostName "shareCommon" ] false (config.flake.lib.nixos.hosts or { });
      commonModule =
        config.flake.nixosModules.hosts-common
          or (throw "Host ${hostName} has shareCommon enabled but flake.nixosModules.hosts-common is missing");
    in
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          _module.args = {
            inherit
              hostName
              inputs
              metaOwner
              secretsRoot
              ;
          };
        }
      ]
      ++ lib.optionals shareCommon [ commonModule ]
      ++ [ module ];
      specialArgs = {
        inherit
          inputs
          hostName
          metaOwner
          secretsRoot
          ;
      };
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

  config.flake = {
    nixosConfigurations = nixosConfigs;
    checks = lib.mkMerge checksMap;
  };
}
