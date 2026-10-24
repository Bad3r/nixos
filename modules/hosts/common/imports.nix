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
  fc660cKeyboardExists = lib.hasAttrByPath [ "flake" "nixosModules" "hardware-fc660c" ] config;
  workloadNetworksExists = lib.hasAttrByPath [ "flake" "nixosModules" "workloads-networks" ] config;
  workloadVmsExists = lib.hasAttrByPath [ "flake" "nixosModules" "workloads-vms" ] config;
  workloadServicesExists = lib.hasAttrByPath [ "flake" "nixosModules" "workloads-services" ] config;
  workloadSharingExists = lib.hasAttrByPath [ "flake" "nixosModules" "workloads-sharing" ] config;
  workloadNamesExists = lib.hasAttrByPath [ "flake" "nixosModules" "workloads-names" ] config;
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
      r2Secrets.enable = lib.mkDefault true;
      virustotalSecrets.enable = lib.mkDefault true;
    };

    # repoGpg has no consumer (nothing reads .secretFile/.secretExists): stays at its own
    # enable = false default rather than decrypting the repo signing key fleet-wide unused.
    home-manager.sharedModules = lib.mkAfter (
      lib.optionals repoGpgModuleExists [
        (lib.getAttrFromPath [ "self" "homeManagerModules" "repoGpg" ] inputs)
      ]
    );
  };
in
{
  # Shared fleet composition. Chassis-specific modules (vendor nixos-hardware
  # profiles, host support modules) stay host-owned in modules/hosts/<host>/.
  flake.nixosModules.hosts-common.imports = [
    # Required infrastructure (exported NixOS modules)
    # Note: base includes Stylix via modules/stylix/stylix.nix contribution
    config.flake.nixosModules.base
    config.flake.csec.wordlists
    config.flake.nixosModules.sopsRuntime
    config.flake.nixosModules.repoSecrets
    config.flake.nixosModules.ssh
    config.flake.nixosModules.bluetooth
    config.flake.nixosModules.nvidia-gpu

    # External hardware modules shared by the current fleet
    inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
  ]
  # Optional modules (graceful degradation)
  ++ lib.optionals duplicatiModuleExists [ config.flake.nixosModules."duplicati-r2" ]
  ++ lib.optionals mirrorRootModuleExists [ config.flake.nixosModules.mirror-root ]
  ++ lib.optionals fc660cKeyboardExists [ config.flake.nixosModules."hardware-fc660c" ]
  ++ lib.optionals workloadNetworksExists [ config.flake.nixosModules."workloads-networks" ]
  ++ lib.optionals workloadVmsExists [ config.flake.nixosModules."workloads-vms" ]
  ++ lib.optionals workloadServicesExists [ config.flake.nixosModules."workloads-services" ]
  ++ lib.optionals workloadSharingExists [ config.flake.nixosModules."workloads-sharing" ]
  ++ lib.optionals workloadNamesExists [ config.flake.nixosModules."workloads-names" ]
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
