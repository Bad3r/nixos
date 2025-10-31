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
  getVirtualizationModule =
    name:
    if lib.hasAttrByPath [ "virtualization" name ] nixosModules then
      lib.getAttrFromPath [ "virtualization" name ] nixosModules
    else
      null;
  hardwareModules = [
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.system76-darp6
  ];
  metaOwner = import ../../lib/meta-owner-profile.nix;
  baseModules = lib.filter (module: module != null) [
    (getModule "base")
    (getModule "system76-support")
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
    flake.homeManagerModules = lib.mkDefault (flake.homeManagerModules or { });
    imports = [
      ../home-manager/base.nix
      ../style/stylix.nix
      ../home/context7-secrets.nix
      ../home/r2-secrets.nix
    ]
    ++ hardwareModules
    ++ baseModules
    ++ virtualizationModules
    ++ lib.optional (hasModule "ssh") nixosModules.ssh;

    nixpkgs.allowedUnfreePackages = lib.mkAfter [
      "p7zip-rar"
      "rar"
      "unrar"
    ];

    # Hardware support
    hardware.system76.extended.enable = true;

    # Security & authentication
    security.polkit.wheelPowerManagement.enable = true;

    # Gaming & performance
    programs = {
      steam.extended.enable = true;
      mangohud.extended.enable = true;
      rip2.extended.enable = true;
    };
  };

  # Export the System76 configuration so the flake exposes it under nixosConfigurations
  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "system76" "module" ] config) {
    nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          _module.args.metaOwner = metaOwner;
        }
        (
          { lib, ... }:
          lib.mkIf (selfRevision != null) {
            system.configurationRevision = lib.mkDefault selfRevision;
          }
        )
        config.configurations.nixos.system76.module
      ];
      specialArgs = {
        inherit metaOwner;
      };
    };
  };
}
