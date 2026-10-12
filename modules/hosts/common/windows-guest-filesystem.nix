_:
let
  body =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.host.virtualization.windowsGuest;
      winfspVersion = "2.1.25156";
      winfsp = pkgs.fetchurl {
        url = "https://github.com/winfsp/winfsp/releases/download/v2.1/winfsp-${winfspVersion}.msi";
        hash = "sha256-Bzpw4A93Qj40vtmLhuYA3vkzk7pYIiBPrFeikyTbn3o=";
      };
      # Keep the host closure limited to the signed Windows 11 filesystem files.
      driver = pkgs.runCommand "windows-guest-viofs" { } ''
        mkdir -p "$out"
        for file in viofs.inf viofs.cat viofs.sys virtiofs.exe; do
          cp "${pkgs.virtio-win}/viofs/w11/amd64/$file" "$out/$file"
        done
      '';
      manifest = pkgs.writeText "windows-guest-filesystem.json" (
        builtins.toJSON {
          virsh = "${config.virtualisation.libvirtd.package}/bin/virsh";
          uri = "qemu:///system";
          domain = cfg.name;
          transfer_dir = cfg.transferDir;
          script = ../../../scripts/windows-guest/shared-folder.ps1;
          quick_access_script = ../../../scripts/windows-guest/quick-access.ps1;
          guest_services_firewall_script = ../../../scripts/windows-guest/guest-services-firewall.ps1;
          winfsp_version = winfspVersion;
          files = {
            "winfsp.msi" = winfsp;
            "viofs.inf" = "${driver}/viofs.inf";
            "viofs.cat" = "${driver}/viofs.cat";
            "viofs.sys" = "${driver}/viofs.sys";
            "virtiofs.exe" = "${driver}/virtiofs.exe";
            "pin-quick-access.ps1" = ../../../scripts/windows-guest/pin-quick-access.ps1;
          };
        }
      );
      provision = pkgs.writeShellScript "windows-guest-filesystem" ''
        exec ${lib.getExe pkgs.uv} run --offline --no-project --no-managed-python \
          --python ${pkgs.python314}/bin/python3 \
          ${../../../scripts/windows-guest/provision.py} --config ${manifest}
      '';
    in
    {
      config = lib.mkIf cfg.enable {
        systemd.services.windows-guest-filesystem = {
          description = "Reconcile Windows guest firewall and virtiofs access through the QEMU guest agent";
          after = [
            "libvirtd.service"
            "nixvirt.service"
          ];
          requires = [ "libvirtd.service" ];
          environment.UV_CACHE_DIR = "/var/cache/windows-guest-filesystem";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = provision;
            TimeoutStartSec = "15min";
            CacheDirectory = "windows-guest-filesystem";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
          };
        };
        systemd.timers.windows-guest-filesystem = {
          description = "Check Windows guest provisioning when the guest is running";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "30s";
            OnUnitInactiveSec = "1min";
          };
        };
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
