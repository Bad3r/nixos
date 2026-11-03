_:
let
  hostKeysModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.workloads;
      stateDir = "/var/lib/workloads";
      keyDir = "${stateDir}/host-keys";
      knownHosts = "${stateDir}/ssh_known_hosts";
      captureUnit = "workloads-host-key@";
      hookName = "workloads-host-key";

      # The agent reads the key without the network; a guest without an interface has no SSH to pin.
      guests = lib.filterAttrs (
        _: guest: guest.ensure == "present" && guest.guestAgent && guest.hostnames != [ ]
      ) cfg.guests;

      manifest = pkgs.writeText "workloads-host-keys.json" (
        builtins.toJSON {
          inherit keyDir knownHosts;
          guests = lib.mapAttrs (_: guest: {
            inherit (guest) uuid kind;
            inherit (guest) hostnames;
          }) guests;
        }
      );

      python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);
      script = "${python.interpreter} -I ${./_host-keys.py} ${manifest}";
      systemctl = "${config.systemd.package}/bin/systemctl";

      # libvirt waits for a hook, so it only queues the job.
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
            unit="${captureUnit}$1.service"
            if ! ${systemctl} --no-block "$action" "$unit"; then
              echo "${hookName}: cannot queue $action of $unit" >&2
            fi
          ''
      );
    in
    {
      config = lib.mkMerge [
        (lib.mkIf config.virtualisation.libvirtd.enable {
          virtualisation.libvirtd.hooks.qemu.${hookName} = hook;
          # libvirtd-config links hooks only when libvirtd starts; this link lands at switch.
          systemd.tmpfiles.settings.workloads-host-keys."/var/lib/libvirt/hooks/qemu.d/${hookName}"."L+".argument =
            "${hook}";
        })
        (lib.mkIf (guests != { }) {
          # Only the guests' own names consult the captured file, so it can never vouch for another host.
          programs.ssh.hosts.${
            lib.concatStringsSep " " (lib.concatMap (guest: guest.hostnames) (lib.attrValues guests))
          } =
            {
              order = 500;
              GlobalKnownHostsFile = "/etc/ssh/ssh_known_hosts ${knownHosts}";
            };

          systemd = {
            tmpfiles.settings.workloads-host-keys.${keyDir}.d = {
              mode = "0700";
              user = "root";
              group = "root";
            };

            # Restarts at switch through its manifest, so undeclared guests lose their entries.
            services.workloads-host-keys = {
              description = "Write the SSH known_hosts file of workload guests";
              wantedBy = [ "multi-user.target" ];
              requires = [ "libvirtd.service" ];
              after = [
                "libvirtd.service"
                "systemd-tmpfiles-setup.service"
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${script} refresh ${systemctl} ${captureUnit}%%i.service";
              };
            };

            services.${captureUnit} = {
              description = "Record the SSH host key of the %i workload guest";
              wants = [ "workloads-host-keys.service" ];
              after = [ "workloads-host-keys.service" ];
              # The next start of the guest records its key with the new manifest.
              restartIfChanged = false;
              serviceConfig = {
                Type = "oneshot";
                # The active unit records that the current run of the guest has its key recorded.
                RemainAfterExit = true;
                # Windows creates its key only once firstlogon.ps1 installs OpenSSH.
                TimeoutStartSec = "infinity";
                ExecStart = "${script} capture %i";
              };
            };
          };
        })
      ];
    };
in
{
  flake.nixosModules."workloads-vms" = hostKeysModule;
}
