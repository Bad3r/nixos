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
  roleHelpers =
    (config.flake.lib.nixos.roles or { }) // (config._module.args.nixosRoleHelpers or { });
  getRoleModule =
    name:
    let
      getRole = roleHelpers.getRole or (_: null);
      roleValue = getRole name;
    in
    if roleValue != null then
      roleValue
    else if lib.hasAttrByPath [ "roles" name ] nixosModules then
      lib.getAttrFromPath [ "roles" name ] nixosModules
    else
      throw (
        "system76 host requires role " + name + " but it was not found in helpers or flake.nixosModules"
      );
  roleModules = map getRoleModule roleNames;
  getVirtualizationModule =
    name:
    if lib.hasAttrByPath [ "virtualization" name ] nixosModules then
      lib.getAttrFromPath [ "virtualization" name ] nixosModules
    else
      null;
  roleNames = [
    "desktop"
    "files"
    "warp-client"
    "pentesting-devshell"
    "chat"
  ];
  workstationModule = getModule "workstation";
  baseModules = lib.filter (module: module != null) [
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.system76-darp6
    (getModule "packages")
    workstationModule
    (getModule "system76-support")
    (getModule "security")
    (getModule "hardware-lenovo-y27q-20")
    (getModule "duplicati-r2")
    (getModule "virt")
  ];
  virtualizationModules = lib.filter (module: module != null) (
    map getVirtualizationModule [
      "docker"
      "libvirt"
      "ovftool"
      "vmware"
    ]
  );
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
    _module.check = false;
    imports =
      baseModules
      ++ virtualizationModules
      ++ roleModules
      ++ lib.optional (hasModule "ssh") nixosModules.ssh;

    nixpkgs.allowedUnfreePackages = lib.mkAfter [
      "p7zip-rar"
      "rar"
      "unrar"
    ];
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
