{
  config,
  lib,
  inputs,
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
  duplicatiModuleExists = lib.hasAttrByPath [ "flake" "nixosModules" "duplicati-r2" ] config;
  mirrorRootModuleExists = lib.hasAttrByPath [ "flake" "nixosModules" "mirror-root" ] config;
  lenovoMonitorExists = lib.hasAttrByPath [ "flake" "nixosModules" "hardware-lenovo-y27q-20" ] config;
  repoGpgModuleExists = lib.hasAttrByPath [
    "self"
    "homeManagerModules"
    "repoGpg"
  ] inputs;

  body = _: {
    # Cybersecurity wordlist symlinks under /usr/share/wordlists/
    csec.wordlists.enable = true;

    security = {
      polkit.wheelPowerManagement.enable = true;
      # Do not grant broad systemd unit management without explicit elevation.
      polkit.wheelSystemdManagement.enable = false;
      repoSecrets.enable = lib.mkDefault true;
      r2CloudSecrets.enable = lib.mkDefault true;
    };

    home-manager.users.${metaOwner.username}.home = {
      context7Secrets.enable = lib.mkDefault true;
      geckoSecrets.enable = lib.mkDefault true;
      greptileSecrets.enable = lib.mkDefault true;
      r2Secrets.enable = lib.mkDefault true;
      virustotalSecrets.enable = lib.mkDefault true;
    }
    // lib.optionalAttrs repoGpgModuleExists {
      repoGpg.enable = lib.mkDefault true;
    };

    home-manager.sharedModules = lib.mkAfter (
      lib.optionals repoGpgModuleExists [
        (lib.getAttrFromPath [ "self" "homeManagerModules" "repoGpg" ] inputs)
      ]
    );
  };
in
{
  # Shared fleet composition. Chassis-specific modules stay host-owned;
  # system76/imports.nix carries the current hardware-profile example.
  flake.nixosModules.hosts-common.imports = [
    # Required infrastructure (exported NixOS modules)
    # Note: base includes Stylix via modules/stylix/stylix.nix contribution
    config.flake.nixosModules.base
    config.flake.csec.wordlists
    config.flake.nixosModules.sopsRuntime
    config.flake.nixosModules.repoSecrets
    config.flake.nixosModules.lang
    config.flake.nixosModules.ssh
    config.flake.nixosModules.bluetooth
    config.flake.nixosModules.nvidia-gpu
    config.flake.nixosModules.zshKeybindings

    # External hardware modules shared by the current fleet
    inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
  ]
  # Optional modules (graceful degradation)
  ++ lib.optionals duplicatiModuleExists [ config.flake.nixosModules."duplicati-r2" ]
  ++ lib.optionals mirrorRootModuleExists [ config.flake.nixosModules.mirror-root ]
  ++ lib.optionals lenovoMonitorExists [ config.flake.nixosModules."hardware-lenovo-y27q-20" ]
  ++ [
    (
      { lib, ... }:
      lib.mkIf (selfRevision != null) {
        system.configurationRevision = lib.mkDefault selfRevision;
      }
    )
    body
  ];
}
