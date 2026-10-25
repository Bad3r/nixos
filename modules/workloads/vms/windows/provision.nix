{ config, ... }:
let
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;

  provisionModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.workloads) networks;
      guests = lib.filterAttrs (
        _: guest: guest.kind == "windows" && guest.ensure == "present"
      ) config.workloads.guests;
      python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);
      hookName = "workloads-provision";

      winfsp = rec {
        version = "2.1.25156";
        sha256 = "073a70e00f77423e34bed98b86e600def93393ba5822204fac57a29324db9f7a";
        msi = pkgs.fetchurl {
          url = "https://github.com/winfsp/winfsp/releases/download/v2.1/winfsp-${version}.msi";
          inherit sha256;
        };
      };

      spec =
        _: guest:
        let
          inherit (guest) windows;
          gateways = lib.unique (
            map (interface: networks.${interface.network}.gateway) (lib.attrValues guest.interfaces)
          );
        in
        {
          inherit (guest) uuid;
          account = windows.account.name;
          inherit (windows.account) authorizedKeys autoLogon;
          passwordFile = config.sops.secrets.${windows.account.passwordSecret}.path;
          productKeyFile =
            if windows.productKeySecret == null then
              null
            else
              config.sops.secrets.${windows.productKeySecret}.path;
          officeInstaller =
            if windows.office.installer == null then
              null
            else
              config.workloads.media.${windows.office.installer}.path;
          inherit gateways;
          services = lib.mapAttrsToList (name: service: {
            inherit name;
            inherit (service) port protocol;
            remote = gateways;
          }) windows.services;
          virtiofs = {
            inherit (windows.virtiofs) mode;
            shares = lib.mapAttrsToList (tag: letter: {
              inherit tag letter;
            }) windows.virtiofs.driveLetters;
          };
          # Pushed by the guest agent, so shares declared after the installation get it too.
          winfsp =
            if windows.virtiofs.driveLetters == { } then
              null
            else
              {
                inherit (winfsp) version sha256;
                msi = "${winfsp.msi}";
              };
          install = guest.install.media != [ ];
          osDisk = "${guest.stateDir}/${lib.head (lib.attrNames guest.disks)}.qcow2";
        };

      # The Office step copies its installer from the staged media.
      mediaUnit = lib.optional (lib.any (guest: guest.windows.office.installer != null) (
        lib.attrValues guests
      )) "workloads-vm-media.service";

      manifest = pkgs.writeText "workloads-provision.json" (builtins.toJSON (lib.mapAttrs spec guests));

      # libvirt waits for a hook, so it only queues the job; failing a
      # "started" hook would kill the guest.
      hook = pkgs.writeShellScript hookName (
        if guests == { } then
          "exit 0\n"
        else
          ''
            case "$1" in
              ${lib.concatStringsSep " | " (lib.attrNames guests)}) ;;
              *) exit 0 ;;
            esac
            case "$2" in
              started | reconnect) action=start ;;
              stopped) action=stop ;;
              *) exit 0 ;;
            esac
            unit="workloads-provision@$1.service"
            if ! ${config.systemd.package}/bin/systemctl --no-block "$action" "$unit"; then
              echo "${hookName}: cannot queue $action of $unit" >&2
            fi
          ''
      );
    in
    {
      # libvirtd scans qemu.d per call, but only once it found a qemu hook at
      # its own start (virHookInitialize; SIGHUP skips it), so the hook exists
      # before any Windows guest does.
      config = lib.mkMerge [
        (lib.mkIf config.virtualisation.libvirtd.enable {
          virtualisation.libvirtd.hooks.qemu.${hookName} = hook;
          # libvirtd-config links hooks only when libvirtd starts; this link lands at switch.
          systemd.tmpfiles.settings.workloads-provision."/var/lib/libvirt/hooks/qemu.d/${hookName}"."L+".argument =
            "${hook}";
        })
        (lib.mkIf (guests != { }) {
          assertions = lib.mapAttrsToList (name: guest: {
            assertion = guest.disks != { };
            message = "workloads.guests.${name}: Windows guests need a disk";
          }) guests;

          systemd = {
            services."workloads-provision@" = {
              description = "Provision the %i workload guest through its guest agent";
              requires = [ "libvirtd.service" ];
              wants = [ "time-sync.target" ] ++ mediaUnit;
              after = [
                "libvirtd.service"
                "time-sync.target"
              ]
              ++ mediaUnit
              ++ sopsInstallSecretsDeps config;
              # A restart at switch would wait for a whole provisioning run; the
              # next start of the guest runs the new steps.
              restartIfChanged = false;
              serviceConfig = {
                Type = "oneshot";
                # The active unit records that the current run of the guest is provisioned.
                RemainAfterExit = true;
                # It waits through the whole installation for the guest agent.
                TimeoutStartSec = "infinity";
                ExecStart = "${python.interpreter} -I ${./_provision.py} ${manifest} %i --scripts ${./_steps}";
              };
            };
          };
        })
      ];
    };
in
{
  flake.nixosModules."workloads-vms" = provisionModule;
}
