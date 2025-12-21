{
  config,
  lib,
  inputs,
  ...
}:
let
  metaOwner = import ../../lib/meta-owner-profile.nix;
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
      # ABSOLUTE MINIMUM: ZERO imports
    ];

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

    # Language support
    languages = {
      clojure.extended.enable = true;
      rust.extended.enable = true;
      java.extended.enable = true;
      python.extended.enable = true;
      go.extended.enable = true;
    };
  };

  # Export the System76 configuration so the flake exposes it under nixosConfigurations
  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "system76" "module" ] config) {
    nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          _module.args.metaOwner = metaOwner;
          _module.args.inputs = inputs;
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
        inherit inputs metaOwner;
      };
    };
  };
}
