_:
let
  leasesModule =
    {
      config,
      lib,
      pkgs,
      utils,
      ...
    }:
    let
      libvirtNetworks = lib.filterAttrs (_: network: network.libvirt.enable) config.workloads.networks;
      networks = lib.filterAttrs (_: network: network.libvirt.bindLeases) libvirtNetworks;
      leaseDir = "/var/lib/libvirt/dnsmasq";

      declared = pkgs.writeText "workload-leases.json" (
        builtins.toJSON (
          lib.mapAttrsToList (name: network: {
            inherit name;
            inherit (network) bridge gateway subnet;
            # libvirt's lease helper rewrites it on every lease event.
            status = "${leaseDir}/${network.bridge}.status";
          }) networks
        )
      );

      # Serialized, since the watcher and a propagated reload may run it at once.
      refill = pkgs.writeShellApplication {
        name = "workload-leases-refill";
        runtimeInputs = [
          pkgs.nftables
          pkgs.util-linux
        ];
        text = ''
          exec flock /run/workload-leases.lock ${pkgs.python3.interpreter} -I ${./_leases.py} ${declared}
        '';
      };

      # Event-driven, with a periodic refill for an event that lands before the
      # watch exists or while a refill runs. The drain has a deadline, so a
      # guest churning its leases cannot starve the refill.
      watch = pkgs.writeShellApplication {
        name = "workload-leases-watch";
        runtimeInputs = [ pkgs.inotify-tools ];
        text = ''
          ${lib.getExe refill}
          inotifywait -m -q -e close_write,moved_to --format %f \
            --include '(^|/)(${
              lib.concatMapStringsSep "|" (network: lib.escapeRegex network.bridge) (lib.attrValues networks)
            })\.status$' \
            ${leaseDir} | while :; do
            status=0
            read -r -t 30 _ || status=$?
            if [ "$status" -eq 0 ]; then
              for _ in 1 2 3 4 5; do
                read -r -t 0.2 _ || break
              done
            elif [ "$status" -le 128 ]; then
              exit 1
            fi
            ${lib.getExe refill}
          done
        '';
      };

      linkLocalUnit = name: network: {
        name = "workload-linklocal-${name}";
        value =
          let
            device = "${utils.escapeSystemdPath "/sys/subsystem/net/devices/${network.bridge}"}.device";
          in
          {
            description = "Stop ${network.bridge} learning addresses from link-local frames";
            # A switch starts no unit wanted only by an already plugged device.
            wantedBy = [
              "multi-user.target"
              device
            ];
            bindsTo = [ device ];
            after = [ device ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            # The bridge learns from link-local frames before any prerouting rule sees them.
            script = "echo 1 > /sys/class/net/${network.bridge}/bridge/no_linklocal_learn";
          };
      };

      # Guests attach only once the binding is loaded.
      networkUnit = name: _: {
        name = "workloads-vm-net-${name}";
        value = {
          requires = [ "workload-leases.service" ];
          after = [ "workload-leases.service" ];
        };
      };
    in
    {
      config = lib.mkMerge [
        # Pinned MACs mean nothing if a link-local frame can move them.
        { systemd.services = lib.mapAttrs' linkLocalUnit libvirtNetworks; }

        (lib.mkIf (networks != { }) {
          systemd.tmpfiles.settings.workload-leases.${leaseDir}.d = {
            mode = "0755";
            user = "root";
            group = "root";
          };

          # The service owns `bridge workload-leases`, so a ruleset reload
          # never empties its port pins; it reloads only to recreate the table
          # after a flushing reload.
          systemd.services = lib.mapAttrs' networkUnit networks // {
            workload-leases = {
              description = "Bind guests on workload bridges to their DHCP leases";
              wantedBy = [ "multi-user.target" ];
              requires = [ "nftables.service" ];
              after = [ "nftables.service" ];
              unitConfig.ReloadPropagatedFrom = [ "nftables.service" ];
              startLimitIntervalSec = 0;
              serviceConfig = {
                ExecStart = lib.getExe watch;
                ExecReload = lib.getExe refill;
                Restart = "always";
                RestartSec = 1;
              };
            };
          };
        })
      ];
    };
in
{
  flake.nixosModules."workloads-vms" = leasesModule;
}
