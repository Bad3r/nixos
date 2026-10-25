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
      table = "workload-leases";
      leaseDir = "/var/lib/libvirt/dnsmasq";
      # libvirt's lease helper rewrites it on every lease event.
      statusOf = network: "${leaseDir}/${network.bridge}.status";
      lines = lib.concatStringsSep "\n";

      networkSets = name: ''
        set ports-${name} {
          type iface_index . ether_addr
          flags dynamic, timeout
          timeout 1h
        }
        set seen-${name} {
          type iface_index
          flags dynamic, timeout
          timeout 1h
        }
        set macs-${name} {
          type ether_addr
          flags dynamic, timeout
          timeout 1h
        }
        set leases-${name} {
          type ether_addr . ipv4_addr
          flags timeout
        }
      '';

      # Ports are keyed by ifindex, so a recreated tap starts unpinned.
      networkChains =
        name: network:
        let
          pin = "update @ports-${name} { meta iif . ether saddr } update @seen-${name} { meta iif } update @macs-${name} { ether saddr }";
        in
        ''
          chain guest-${name} {
            meta iif . ether saddr @ports-${name} ${pin} goto pinned-${name}
            meta iif @seen-${name} drop
            ether saddr @macs-${name} drop
            ${pin} goto pinned-${name}
          }

          chain pinned-${name} {
            ether type != { ip, arp } drop
            # Lets a guest whose pair is missing renew and so restore it.
            ip saddr { 0.0.0.0, ${network.subnet} } ip daddr { ${network.gateway}, 255.255.255.255 } udp sport 68 udp dport 67 accept
            ether type ip ether saddr . ip saddr != @leases-${name} drop
            ether type arp meta iif . arp saddr ether != @ports-${name} drop
            # ARP probes announce no address yet.
            arp saddr ip 0.0.0.0 accept
            ether type arp ether saddr . arp saddr ip != @leases-${name} drop
          }
        '';

      refill = pkgs.writeShellApplication {
        name = "workload-leases-refill";
        runtimeInputs = [
          pkgs.jq
          pkgs.nftables
        ];
        text = ''
          shopt -s inherit_errexit
          now=$(date +%s)
          batch=$(
            ${lib.concatMapStrings (
              { name, value }:
              ''
                echo "flush set bridge ${table} leases-${name}"
                if [ -s ${statusOf value} ]; then
                  jq -r --argjson now "$now" '
                    .[]
                    | select((."expiry-time" <= 0 or ."expiry-time" > $now)
                        and (."mac-address" | test("^([0-9a-f]{2}:){5}[0-9a-f]{2}$"))
                        and (."ip-address" | test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$")))
                    | "add element bridge ${table} leases-${name} { \(."mac-address") . \(."ip-address")"
                      + (if ."expiry-time" > 0 then " timeout \(."expiry-time" - $now)s" else "" end) + " }"
                  ' ${statusOf value}
                fi
              ''
            ) (lib.attrsToList networks)}
          )
          nft -f - <<< "$batch"
        '';
      };

      # Event-driven, with a periodic refill for an event that lands before the
      # watch exists or while a refill runs.
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
              while read -r -t 0.2 _; do :; done
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
            wantedBy = [ device ];
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
    in
    {
      config = lib.mkMerge [
        # Pinned MACs mean nothing if a link-local frame can move them.
        { systemd.services = lib.mapAttrs' linkLocalUnit libvirtNetworks; }

        (lib.mkIf (networks != { }) {
          networking.nftables.tables.${table} = {
            family = "bridge";
            content = ''
              ${lib.concatMapStrings networkSets (lib.attrNames networks)}
              chain prerouting {
                type filter hook prerouting priority filter; policy accept;
                ${lines (
                  lib.mapAttrsToList (name: network: ''meta ibrname "${network.bridge}" jump guest-${name}'') networks
                )}
              }

              ${lines (lib.mapAttrsToList networkChains networks)}
            '';
          };

          systemd.tmpfiles.settings.workload-leases.${leaseDir}.d = {
            mode = "0755";
            user = "root";
            group = "root";
          };

          systemd.services = {
            workload-leases = {
              description = "Bind leased MAC and address pairs on workload bridges";
              wantedBy = [ "multi-user.target" ];
              requires = [ "nftables.service" ];
              after = [ "nftables.service" ];
              # A ruleset reload empties the sets.
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
