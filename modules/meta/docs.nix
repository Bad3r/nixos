{ config, lib, ... }:
{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      system.build.docs = pkgs.writeTextFile {
        name = "module-documentation";
        text = ''
          # NixOS Configuration Documentation
          ## Generated at: ${toString builtins.currentTime}

          ## System Information
          - Host: ${config.networking.hostName or "unknown"}
          - State Version: ${config.system.stateVersion or "unknown"}

          ## Enabled Modules
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: _: "- ${name}") (config.flake.nixosModules or { })
          )}

          ## Configuration Structure
          - Base modules provide core system functionality
          - Workstation modules provide desktop, laptop, and developer tooling

          ## Module Namespaces
          - nixos.base: Core system configuration
          - nixos.workstation: Desktop and developer workstation features

          ## Directory Organization
          - audio/: Sound subsystem configuration
          - boot/: Boot and initialization
          - hardware/: Hardware-specific modules
          - networking/: Network configuration
          - security/: Security tools and configuration
          - storage/: Filesystem and storage
          - style/: Theming and appearance
          - virtualization/: VMs and containers
          - window-manager/: Desktop environments
        '';
      };
    };
}
