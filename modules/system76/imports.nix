{
  config,
  lib,
  inputs,
  metaOwner,
  ...
}:
let
  system76SupportExists = lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config;
in
{
  configurations.nixos.system76.module = {
    # Shared fleet composition lives in modules/hosts/common/imports.nix; this
    # file carries only System76-chassis modules and host-specific enables.
    imports = [
      inputs.nixos-hardware.nixosModules.system76
    ]
    ++ lib.optionals system76SupportExists [ config.flake.nixosModules.system76-support ];

    # Hardware support; gate the enable on the optional system76-support module
    # that declares hardware.system76.extended so an absent module degrades
    # gracefully instead of aborting on an undeclared option (cf. repoGpg).
    hardware = lib.optionalAttrs system76SupportExists {
      system76.extended.enable = true;
    };

    home-manager.users.${metaOwner.username}.home.greptileSecrets.enable = lib.mkForce false;

    # Gaming & performance
    programs = {
      steam.extended.enable = true;
      rip.extended.enable = true;
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
}
