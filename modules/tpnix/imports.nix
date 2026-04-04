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

  sopsRuntimeReady = false;

  duplicatiModuleExists =
    sopsRuntimeReady && lib.hasAttrByPath [ "flake" "nixosModules" "duplicati-r2" ] config;
  mirrorRootModuleExists = lib.hasAttrByPath [ "flake" "nixosModules" "mirror-root" ] config;
  lenovoMonitorExists = lib.hasAttrByPath [ "flake" "nixosModules" "hardware-lenovo-y27q-20" ] config;
  r2NixosModuleExists =
    sopsRuntimeReady && lib.hasAttrByPath [ "r2-flake" "nixosModules" "default" ] inputs;
  r2HomeModuleExists =
    sopsRuntimeReady && lib.hasAttrByPath [ "r2-flake" "homeManagerModules" "default" ] inputs;
in
{
  configurations.nixos.tpnix.module = {
    imports = [
      config.flake.nixosModules.base
      config.flake.nixosModules.sopsRuntime
      config.flake.nixosModules.repoSecrets
      config.flake.nixosModules.lang
      config.flake.nixosModules.ssh
    ]
    ++ lib.optionals duplicatiModuleExists [ config.flake.nixosModules."duplicati-r2" ]
    ++ lib.optionals mirrorRootModuleExists [ config.flake.nixosModules.mirror-root ]
    ++ lib.optionals r2NixosModuleExists [ inputs."r2-flake".nixosModules.default ]
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
      powerProfiles.backend = "powerprofilesctl";
    };

    security = {
      polkit.wheelPowerManagement.enable = true;
      polkit.wheelSystemdManagement.enable = false;
      repoSecrets.enable = lib.mkForce false;
      r2CloudSecrets.enable = lib.mkForce false;
    };
    home-manager.users.${metaOwner.username} = {
      home = {
        context7Secrets.enable = lib.mkForce false;
        r2Secrets.enable = lib.mkForce false;
        virustotalSecrets.enable = lib.mkForce false;
      };
    };

    home-manager.sharedModules = lib.mkAfter (
      [
        {
          services.espanso = {
            waylandSupport = lib.mkForce false;
            x11Support = lib.mkForce true;
          };
        }
      ]
      ++ lib.optionals r2HomeModuleExists [ inputs."r2-flake".homeManagerModules.default ]
    );
  };

  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "tpnix" "module" ] config) {
    nixosConfigurations.tpnix = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          _module.args = {
            inherit
              metaOwner
              inputs
              secretsRoot
              ;
          };
        }
        (
          { lib, ... }:
          lib.mkIf (selfRevision != null) {
            system.configurationRevision = lib.mkDefault selfRevision;
          }
        )
        config.configurations.nixos.tpnix.module
      ];
      specialArgs = {
        inherit
          inputs
          metaOwner
          secretsRoot
          ;
      };
    };
  };
}
