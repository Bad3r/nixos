{ config, ... }:
let
  inherit (config.flake.nixosModules) ssh;
in
{
  flake.nixosModules."workloads-guest-base" =
    {
      config,
      hostName,
      lib,
      metaOwner,
      modulesPath,
      pkgs,
      ...
    }:
    let
      cfg = config.workloads.guest;
    in
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        ssh
      ];

      options.workloads.guest = {
        spiceAgent = lib.mkEnableOption ''
          the SPICE agent for clipboard, file transfer, and display resizing;
          only a trusted guest with a SPICE display has its channel
        '';
      };

      config = lib.mkMerge [
        {
          networking.hostName = hostName;
          # Guests run under KVM on an x86_64 host.
          nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

          # The layout system.build.images.qemu-efi writes, so a switch over SSH
          # boots the same disk the image seeded.
          boot = {
            loader.systemd-boot.enable = true;
            growPartition = true;
            # The last console is /dev/console, which `virsh console` attaches to.
            kernelParams = [
              "console=tty0"
              "console=ttyS0,115200n8"
            ];
          };
          fileSystems = {
            "/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
              autoResize = true;
            };
            "/boot" = {
              device = "/dev/disk/by-label/ESP";
              fsType = "vfat";
            };
          };

          services.qemuGuest.enable = true;

          services.openssh.settings = {
            KbdInteractiveAuthentication = false;
            # `nixos-rebuild --target-host root@<guest>` deploys as root.
            PermitRootLogin = "prohibit-password";
          };
          # The host's workload table decides who reaches the guest.
          networking.firewall.allowedTCPPorts = [ 22 ];

          users.users = {
            root.openssh.authorizedKeys.keys = metaOwner.sshKeys;
            ${metaOwner.username} = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              openssh.authorizedKeys.keys = metaOwner.sshKeys;
            };
          };
          # The owner's key already logs in as root.
          security.sudo.wheelNeedsPassword = false;

          nix = {
            package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
            settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          };
        }

        (lib.mkIf cfg.spiceAgent {
          services.spice-vdagentd.enable = true;
          # spice-vdagent starts from XDG autostart, which a bare window manager skips.
          services.xserver.desktopManager.runXdgAutostartIfNone = true;
        })
      ];
    };
}
