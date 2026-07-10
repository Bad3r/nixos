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

  inherit (config.flake.lib.nixos.hosts.tpnix) sopsRuntimeReady;

  duplicatiModuleExists =
    sopsRuntimeReady && lib.hasAttrByPath [ "flake" "nixosModules" "duplicati-r2" ] config;
  mirrorRootModuleExists = lib.hasAttrByPath [ "flake" "nixosModules" "mirror-root" ] config;
  lenovoMonitorExists = lib.hasAttrByPath [ "flake" "nixosModules" "hardware-lenovo-y27q-20" ] config;
  repoGpgModuleExists = lib.hasAttrByPath [
    "self"
    "homeManagerModules"
    "repoGpg"
  ] inputs;
in
{
  configurations.nixos.tpnix.module = {
    imports = [
      config.flake.nixosModules.base
      config.flake.csec.wordlists
      config.flake.nixosModules.sopsRuntime
      config.flake.nixosModules.repoSecrets
      config.flake.nixosModules.lang
      config.flake.nixosModules.ssh
      config.flake.nixosModules.bluetooth
      config.flake.nixosModules.zshKeybindings

      # External hardware modules
      inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
    ]
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
    ];

    _module.args = {
      inherit
        metaOwner
        secretsRoot
        ;
    };

    nixpkgs.allowedUnfreePackages = lib.mkAfter [
      "nvidia-settings"
      "nvidia-x11"
      "p7zip-rar"
      "rar"
      "unrar"
    ];

    gui.i3 = {
      integrations = {
        xfsettingsd.enable = false;
      };
      powerProfiles = {
        allowSelection = false;
      };
    };

    security = {
      polkit.wheelPowerManagement.enable = true;
      polkit.wheelSystemdManagement.enable = false;
      repoSecrets.enable = lib.mkDefault true;
      r2CloudSecrets.enable = lib.mkDefault true;
    };

    # Cybersecurity wordlist symlinks under /usr/share/wordlists/
    csec.wordlists.enable = true;
    home-manager.users.${metaOwner.username} = {
      home = {
        context7Secrets.enable = lib.mkDefault true;
        geckoSecrets.enable = lib.mkDefault true;
        greptileSecrets.enable = lib.mkDefault true;
        r2Secrets.enable = lib.mkDefault true;
        virustotalSecrets.enable = lib.mkDefault true;
      }
      // lib.optionalAttrs repoGpgModuleExists {
        repoGpg.enable = lib.mkDefault true;
      };
    };

    home-manager.sharedModules = lib.mkAfter (
      lib.optionals repoGpgModuleExists [
        (lib.getAttrFromPath [ "self" "homeManagerModules" "repoGpg" ] inputs)
      ]
      ++ [
        {
          services.espanso = {
            waylandSupport = lib.mkForce false;
            x11Support = lib.mkForce true;
          };
        }
      ]
    );
  };
}
