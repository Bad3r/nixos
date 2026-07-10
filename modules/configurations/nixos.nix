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
      # shareCommon must be declared explicitly per host: a silent `false`
      # default let an unregistered host build green without the entire
      # hosts-common baseline (hostname, stateVersion, sops pin, ...) and
      # surface only at runtime. The throw is lazy, so enumerating host
      # names (nix eval .#nixosConfigurations --apply builtins.attrNames)
      # still works while any deeper eval of the host aborts.
      hostsRegistry = config.flake.lib.nixos.hosts or { };
      registryHint = "add `${hostName}.shareCommon = true;` (opt in to the hosts-common baseline) or `= false;` (deliberate opt-out) to modules/hosts/common/registry.nix";
      hostEntry =
        hostsRegistry.${hostName}
          or (throw "Host ${hostName} has no entry in flake.lib.nixos.hosts; ${registryHint}");
      shareCommon =
        hostEntry.shareCommon
          or (throw "flake.lib.nixos.hosts.${hostName} does not set shareCommon; ${registryHint}");
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
