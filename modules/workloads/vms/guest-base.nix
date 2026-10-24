{ config, ... }:
let
  inherit (config.flake.nixosModules) ssh;
in
{
  flake.nixosModules."workloads-guest-base" =
    {
      hostName,
      lib,
      metaOwner,
      modulesPath,
      pkgs,
      ...
    }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        ssh
      ];

      config = {
        networking.hostName = hostName;
        # The host constructor's checks read it; nixosSystem's `system` sets only nixpkgs.system.
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
            options = [
              "fmask=0077"
              "dmask=0077"
            ];
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
      };
    };
}
