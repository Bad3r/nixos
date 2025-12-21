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
    imports =
      let
        # Stage 1-2: Apps and hardware
        baseModuleExists = lib.hasAttrByPath [ "flake" "nixosModules" "base" ] config;
        appsEnableExists = builtins.pathExists ./apps-enable.nix;
        system76ModuleExists = (builtins.tryEval inputs.nixos-hardware.nixosModules.system76).success;
        darp6ModuleExists = (builtins.tryEval inputs.nixos-hardware.nixosModules.system76-darp6).success;

        # Stage 3: Base infrastructure (required files)
        stylixExists = builtins.pathExists ../style/stylix.nix;
        customPackagesExists = builtins.pathExists ./custom-packages-overlay.nix;
        sshExists = builtins.pathExists ./ssh.nix;

        # Stage 3: Secrets (conditional - graceful handling)
        context7SecretsPath = ../home/context7-secrets.nix;
        r2SecretsPath = ../home/r2-secrets.nix;

        # Stage 3: Optional flake modules (conditional)
        system76SupportExists = lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config;
        lenovyMonitorExists = lib.hasAttrByPath [ "flake" "nixosModules" "hardware-lenovo-y27q-20" ] config;

        # Stage 4: Virtualization configuration fragment (required)
        virtualizationExists = builtins.pathExists ./virtualization.nix;

        # Stage 4.5: duplicati-r2 configuration fragment (required)
        duplicatiExists = builtins.pathExists ./duplicati.nix;
      in
      assert
        baseModuleExists
        || throw ''
          CRITICAL ERROR: nixosModules.base missing!

          This module is REQUIRED for:
          - Home-manager integration
          - SOPS configuration
          - Base system modules

          Expected location: modules/home-manager/nixos.nix
          Exports: flake.nixosModules.base

          Investigation: Why is this module not being exported?
          See: docs/TECHNICAL_BRIEFING.md for module architecture
        '';
      assert
        appsEnableExists
        || throw ''
          CRITICAL ERROR: apps-enable.nix missing!

          This file contains enable/disable settings for ALL 245 applications.
          Without it, all apps default to disabled state.

          Expected location: modules/system76/apps-enable.nix
          Size: 279 lines (verified in Stage 0.5)

          Investigation: File was removed from imports during metaOwner fix.
          See: docs/disabled-modules-audit-report.md Section 1
        '';
      assert
        system76ModuleExists
        || throw ''
          CRITICAL ERROR: nixos-hardware.nixosModules.system76 missing!

          This module provides System76-specific hardware optimizations:
          - Power management
          - Keyboard backlight controls
          - ACPI configurations
          - System76-specific firmware support

          Source: inputs.nixos-hardware (flake input)
          Expected: Always available from nixos-hardware upstream

          Investigation: Check inputs.nixos-hardware in flake.lock
          Command: nix flake metadata nixos-hardware
          See: docs/disabled-modules-audit-report.md Section 3
        '';
      assert
        darp6ModuleExists
        || throw ''
          CRITICAL ERROR: nixos-hardware.nixosModules.system76-darp6 missing!

          This module provides Darp6-specific hardware support:
          - Model-specific power profiles
          - Display configurations
          - Audio optimizations

          Source: inputs.nixos-hardware (flake input)

          Investigation: Is system76-darp6 still supported in nixos-hardware upstream?
          Command: nix eval inputs.nixos-hardware.nixosModules --apply "builtins.attrNames"
        '';
      assert
        stylixExists
        || throw ''
          CRITICAL ERROR: stylix.nix missing!

          This file provides system-wide theming configuration via Stylix:
          - Color schemes
          - Font configuration
          - Application theming
          - Consistent visual appearance

          Expected location: modules/style/stylix.nix
          Size: 185 lines (verified in Stage 0.5)

          Investigation: File was removed from imports during metaOwner fix.
          See: docs/disabled-modules-audit-report.md Section 1
        '';
      assert
        customPackagesExists
        || throw ''
          CRITICAL ERROR: custom-packages-overlay.nix missing!

          This file provides custom package overlays and modifications:
          - Package customizations
          - Overlay configurations

          Expected location: modules/system76/custom-packages-overlay.nix
          Size: 19 lines (verified in Stage 0.5)

          Investigation: File was removed from imports during metaOwner fix.
        '';
      assert
        sshExists
        || throw ''
          CRITICAL ERROR: ssh.nix missing!

          This file provides SSH configuration for the system76 host:
          - Public key for known_hosts
          - SSH daemon settings

          Expected location: modules/system76/ssh.nix
          Size: 15 lines (verified in Stage 0.5)

          Investigation: File was removed from imports during metaOwner fix.
        '';
      assert
        virtualizationExists
        || throw ''
          CRITICAL ERROR: virtualization.nix missing!

          This configuration fragment enables virtualization support:
          - libvirt/QEMU
          - VMware Workstation
          - OVF Tool
          - Docker (via app modules)

          Expected location: modules/system76/virtualization.nix
          Verified exists in Stage 0.5 investigation

          Investigation: File was removed from imports during metaOwner fix.
          This is a configuration fragment, not a flake module.
        '';
      assert
        duplicatiExists
        || throw ''
          CRITICAL ERROR: duplicati.nix missing!

          This configuration fragment configures the duplicati-r2 backup service:
          - Service configuration
          - R2 storage backend settings

          Expected location: modules/system76/duplicati.nix
          Verified exists in Stage 0.5 investigation

          Investigation: File was removed from imports during metaOwner fix.
          This is a configuration fragment, not a flake module.
        '';

      # Required modules (fail-fast)
      [ config.flake.nixosModules.base ]
      ++ [ ./apps-enable.nix ]
      ++ [
        inputs.nixos-hardware.nixosModules.system76
        inputs.nixos-hardware.nixosModules.system76-darp6
      ]
      # Stage 3: Required infrastructure files
      ++ [
        ../style/stylix.nix
        ./custom-packages-overlay.nix
        ./ssh.nix
      ]
      # Stage 3: Conditional secrets (graceful - no assertion)
      ++ lib.optional (builtins.pathExists context7SecretsPath) context7SecretsPath
      ++ lib.optional (builtins.pathExists r2SecretsPath) r2SecretsPath
      # Stage 3: Optional flake modules (graceful)
      ++ lib.optionals system76SupportExists [ config.flake.nixosModules.system76-support ]
      ++ lib.optionals lenovyMonitorExists [ config.flake.nixosModules."hardware-lenovo-y27q-20" ]
      # Stage 4: Virtualization configuration fragment (required)
      ++ [ ./virtualization.nix ]
      # Stage 4.5: duplicati-r2 configuration fragment (required)
      ++ [ ./duplicati.nix ]
      # Stage 5: System configuration files (core system functionality)
      ++ [
        ./bluetooth.nix
        ./boot.nix
        ./hardware-config.nix
        ./services.nix
        ./network.nix
        ./xserver.nix
        ./window-manager.nix
        ./pipewire.nix
        ./dbus.nix
        ./packages.nix
        ./fonts.nix
        ./terminal.nix
        ./editors.nix
        ./security-tools.nix
        ./graphics-support.nix
        ./nvidia-gpu.nix
        ./gnome-keyring.nix
        ./firmware-manager-fix.nix
        ./nix-settings.nix
        ./nix-substituters.nix
        ./nix-ld.nix
        ./state-version.nix
        ./hostname.nix
        ./host-id.nix
        ./domain.nix
        ./sops.nix
        ./sudo.nix
        ./su.nix
        ./tmp.nix
        ./xdg.nix
        ./zsh.nix
        ./ssh-x11.nix
        ./gsettings.nix
        ./color-profile.nix
        ./appimage-support.nix
        ./home-manager-apps.nix
        ./home-manager-gui.nix
        ./dotool.nix
        ./support.nix
        ./apps-base.nix
        ./teamviewer.nix
        ./r2-quickstart.nix
        ./ghq.nix
        ./usbguard.nix
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
