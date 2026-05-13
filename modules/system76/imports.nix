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

  # Optional flake module checks
  system76SupportExists = lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config;
  lenovyMonitorExists = lib.hasAttrByPath [ "flake" "nixosModules" "hardware-lenovo-y27q-20" ] config;
  repoGpgModuleExists = lib.hasAttrByPath [
    "self"
    "homeManagerModules"
    "repoGpg"
  ] inputs;
in
{
  configurations.nixos.system76.module = {
    # NOTE: All modules/system76/*.nix files are auto-imported by import-tree
    # and contribute to this aggregator via flake-parts. Only actual NixOS
    # modules (exported via flake.nixosModules.* or from external inputs)
    # should be imported here.
    imports = [
      # Required infrastructure (exported NixOS modules)
      # Note: base includes Stylix via modules/style/stylix.nix contribution
      config.flake.nixosModules.base
      config.flake.csec.wordlists
      config.flake.nixosModules.sopsRuntime
      config.flake.nixosModules.repoSecrets
      config.flake.nixosModules.lang
      config.flake.nixosModules.ssh
      config.flake.nixosModules.bluetooth
      config.flake.nixosModules."duplicati-r2"
      config.flake.nixosModules.mirror-root
      config.flake.nixosModules.zshKeybindings

      # External hardware modules
      inputs.nixos-hardware.nixosModules.system76
    ]
    # Optional modules (graceful degradation)
    ++ lib.optionals system76SupportExists [ config.flake.nixosModules.system76-support ]
    ++ lib.optionals lenovyMonitorExists [ config.flake.nixosModules."hardware-lenovo-y27q-20" ]
    ++ [
      (
        { lib, ... }:
        lib.mkIf (selfRevision != null) {
          system.configurationRevision = lib.mkDefault selfRevision;
        }
      )
    ];

    # Pass shared module args to all imported modules
    _module.args = {
      inherit
        metaOwner
        secretsRoot
        ;
    };

    nixpkgs.allowedUnfreePackages = lib.mkAfter [
      "p7zip-rar"
      "rar"
      "unrar"
    ];

    # Hardware support
    hardware.system76.extended.enable = true;

    # Cybersecurity wordlist symlinks under /usr/share/wordlists/
    csec.wordlists.enable = true;

    # Security & authentication
    security = {
      polkit.wheelPowerManagement.enable = true;
      # Do not grant broad systemd unit management without explicit elevation.
      polkit.wheelSystemdManagement.enable = false;
      r2CloudSecrets.enable = lib.mkForce false;
    };
    home-manager.users.${metaOwner.username}.home = {
      context7Secrets.enable = lib.mkDefault true;
      greptileSecrets.enable = lib.mkForce false;
      repoGpg.enable = lib.mkDefault true;
      r2Secrets.enable = lib.mkForce false;
      virustotalSecrets.enable = lib.mkDefault true;
    };

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

    home-manager.sharedModules = lib.mkAfter (
      lib.optionals repoGpgModuleExists [
        (lib.getAttrFromPath [ "self" "homeManagerModules" "repoGpg" ] inputs)
      ]
    );
  };
}
