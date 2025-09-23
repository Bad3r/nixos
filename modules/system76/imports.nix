{
  config,
  lib,
  inputs,
  ...
}:
let
  flake = config.flake or { };
  nixosModules = flake.nixosModules or { };
  hasModule = name: lib.hasAttr name nixosModules;
  getModule = name: if hasModule name then lib.getAttr name nixosModules else null;
  roleNames = [
    "role-dev"
    "role-media"
    "role-net"
    "role-gaming"
    "role-files"
    "role-xserver"
  ];
  roleModules = lib.filter (module: module != null) (map getModule roleNames);
  baseModules = lib.filter (module: module != null) [
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.system76-darp6
    (getModule "workstation")
    (getModule "system76-support")
  ];
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
    imports = baseModules ++ roleModules ++ lib.optional (hasModule "ssh") nixosModules.ssh;
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
