/*
  Package: libvirt
  Description: Virtualization API and daemon that manages QEMU/KVM guests and their networks.
  Homepage: https://libvirt.org/
  Documentation: https://libvirt.org/docs.html
  Repository: https://gitlab.com/libvirt/libvirt

  Summary:
    * Runs the system libvirtd (qemu:///system) with QEMU/KVM, and puts virsh and qemu-system-x86_64 on PATH.
    * QEMU runs as qemu-libvirtd; guests get swtpm TPMs, virtiofsd shares, and OVMF firmware with
      Microsoft keys enrolled for domains that request enrolled-keys.

  Options:
    -c qemu:///system: Connect to the system daemon; a read-write connection asks for admin authentication.
    -r: Open a read-only connection, which needs no authentication.

  Notes:
    * Plain virsh as the owner talks to qemu:///session: no LIBVIRT_DEFAULT_URI is set, so nothing
      raises a system prompt by accident.
    * No user joins the libvirtd group; every read-write qemu:///system connection authenticates
      through polkit, and root connections bypass polkit.
    * libvirtd and virtlockd do not restart on switch: after a libvirt bump, `systemctl restart
      libvirtd` keeps running guests (KillMode=process).
    * libvirt-guests shuts guests down on host shutdown and resumes none at boot; autostart is per
      object.
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
            vhostUserPackages = [ pkgs.virtiofsd ];
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

        # Not libvirt's auth_admin_keep: no process in the session rides a
        # recent authentication. Sorts ahead of the nixpkgs libvirtd-group rule.
        security.polkit.extraConfig = lib.mkBefore ''
          polkit.addRule(function(action, subject) {
            if (action.id === "org.libvirt.unix.manage") {
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
