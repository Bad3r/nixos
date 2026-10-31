/*
  Package: libvirt
  Description: Virtualization API and daemon that manages QEMU/KVM guests and their networks.
  Homepage: https://libvirt.org/
  Documentation: https://libvirt.org/docs.html
  Repository: https://gitlab.com/libvirt/libvirt

  Options:
    -c qemu:///system: Connect to the system daemon.
    -r: Open a read-only connection.

  Notes:
    * Plain `virsh` connects to qemu:///session.
    * Wheel members manage system guests without a password.
    * libvirtd does not restart on switch; restart it after a libvirt bump, running guests survive.
    * Guests shut down with the host and none resume at boot.
*/
_:
let
  LibvirtModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.libvirt.extended;
    in
    {
      options.programs.libvirt.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the libvirt daemon.";
        };

        package = lib.mkPackageOption pkgs "libvirt" { };

        qemuPackage = lib.mkPackageOption pkgs "qemu_kvm" { };

        virtiofsdPackage = lib.mkPackageOption pkgs "virtiofsd" { };
      };

      config = lib.mkIf cfg.enable {
        virtualisation.libvirtd = {
          enable = true;
          inherit (cfg) package;
          onBoot = "ignore";
          onShutdown = "shutdown";
          shutdownTimeout = 90;
          firewallBackend = "nftables";
          qemu = {
            package = cfg.qemuPackage;
            runAsRoot = false;
            swtpm.enable = true;
            vhostUserPackages = [ cfg.virtiofsdPackage ];
            firmwarePackages.ovmf-full = pkgs.OVMFFull.fd;
            # The first line is the nixpkgs default. Consoles without a listen
            # address get a unix socket that only libvirt clients reach, instead
            # of a password-less port on 127.0.0.1 that any local user can open.
            verbatimConfig = ''
              namespaces = []
              spice_auto_unix_socket = 1
              vnc_auto_unix_socket = 1
            '';
          };
        };

        # Sorts ahead of the nixpkgs libvirtd-group rule.
        security.polkit.extraConfig = lib.mkBefore ''
          polkit.addRule(function(action, subject) {
            if (action.id === "org.libvirt.unix.manage") {
              if (subject.isInGroup("wheel")) {
                return polkit.Result.YES;
              }
              return polkit.Result.AUTH_ADMIN;
            }
          });
        '';
      };
    };
in
{
  flake.nixosModules.apps.libvirt = LibvirtModule;
}
