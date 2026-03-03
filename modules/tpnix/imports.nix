{
  config,
  lib,
  inputs,
  secretsRoot,
  metaOwner,
  ...
}:
let
  selfRevision =
    let
      self = inputs.self or null;
    in
    if self != null then
      let
        dirty = self.dirtyRev or null;
        rev = self.rev or null;
      in
      if dirty != null then dirty else rev
    else
      null;

  exportedI3 = import ../apps/i3wm/nixos.nix;
  i3Module = lib.attrByPath [ "flake" "nixosModules" "window-manager" "i3" ] null exportedI3;
in
{
  configurations.nixos.tpnix.module = {
    imports = [
      config.flake.nixosModules.base
      config.flake.nixosModules.lang
      config.flake.nixosModules.ssh
    ]
    ++ lib.optionals (i3Module != null) [ i3Module ]
    ++ [
      (
        { lib, ... }:
        lib.mkIf (selfRevision != null) {
          system.configurationRevision = lib.mkDefault selfRevision;
        }
      )
    ];

    _module.args = {
      inherit
        metaOwner
        secretsRoot
        ;
    };
  };

  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "tpnix" "module" ] config) {
    nixosConfigurations.tpnix = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          _module.args = {
            inherit
              metaOwner
              inputs
              secretsRoot
              ;
          };
        }
        (
          { lib, ... }:
          lib.mkIf (selfRevision != null) {
            system.configurationRevision = lib.mkDefault selfRevision;
          }
        )
        config.configurations.nixos.tpnix.module
      ];
      specialArgs = {
        inherit
          inputs
          metaOwner
          secretsRoot
          ;
      };
    };
  };
}
