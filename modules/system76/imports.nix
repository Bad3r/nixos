{
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (config.flake) nixosModules;
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
in
{
  configurations.nixos.system76.module = {
    imports = [
      inputs.nixos-hardware.nixosModules.system76
      inputs.nixos-hardware.nixosModules.system76-darp6
      nixosModules.workstation
      nixosModules.system76-support
      nixosModules."role-dev"
      nixosModules."role-media"
      nixosModules."role-net"
      nixosModules."role-gaming"
    ]
    ++ lib.optional (lib.hasAttr "ssh" nixosModules) nixosModules.ssh;
  };

  # Export the System76 configuration so the flake exposes it under nixosConfigurations
  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "system76" "module" ] config) {
    nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        (
          { lib, ... }:
          lib.mkIf (selfRevision != null) {
            system.configurationRevision = lib.mkDefault selfRevision;
          }
        )
        config.configurations.nixos.system76.module
      ];
    };
  };
}
