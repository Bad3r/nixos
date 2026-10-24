_:
let
  leasesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      networks = lib.filterAttrs (
        _: network: network.libvirt.enable && network.libvirt.bindLeases
      ) config.workloads.networks;
      table = "workload-leases";
      setOf = name: "leases-${name}";
      # libvirt's lease helper rewrites it on every lease event.
      statusOf = network: "/var/lib/libvirt/dnsmasq/${network.bridge}.status";

      # The bridge's own frames take the output hook, so these see guest ports only.
      networkRules =
        name: network:
        let
          dev = ''meta ibrname "${network.bridge}"'';
          set = "@${setOf name}";
        in
        [
          "${dev} ether type != { ip, arp } drop"
          "${dev} ip saddr 0.0.0.0 udp sport 68 udp dport 67 accept"
          "${dev} ether type ip ether saddr . ip saddr != ${set} drop"
          # ARP probes announce no address yet.
          "${dev} arp saddr ip 0.0.0.0 accept"
          "${dev} ether type arp ether saddr . arp saddr ip != ${set} drop"
          "${dev} ether type arp arp saddr ether . arp saddr ip != ${set} drop"
        ];

      # One transaction per run; an empty or missing lease file leaves the set empty.
      refill = pkgs.writeShellApplication {
        name = "workload-leases";
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
                echo "flush set bridge ${table} ${setOf name}"
                if [ -s ${statusOf value} ]; then
                  jq -r --argjson now "$now" '
                    .[]
                    | select((."expiry-time" <= 0 or ."expiry-time" > $now)
                        and (."mac-address" | test("^([0-9a-f]{2}:){5}[0-9a-f]{2}$"))
                        and (."ip-address" | test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$")))
                    | "add element bridge ${table} ${setOf name} { \(."mac-address") . \(."ip-address") }"
                  ' ${statusOf value}
                fi
              ''
            ) (lib.attrsToList networks)}
          )
          nft -f - <<< "$batch"
        '';
      };
    in
    {
      config = lib.mkIf (networks != { }) {
        networking.nftables.tables.${table} = {
          family = "bridge";
          content = ''
            ${lib.concatMapStrings (name: ''
              set ${setOf name} {
                type ether_addr . ipv4_addr
              }
            '') (lib.attrNames networks)}
            chain prerouting {
              type filter hook prerouting priority filter; policy accept;
              ${lib.concatStringsSep "\n" (lib.concatLists (lib.mapAttrsToList networkRules networks))}
            }
          '';
        };

        systemd = {
          # A reload of the ruleset empties the sets, so this refills them after it.
          services.workload-leases = {
            description = "Bind leased MAC and address pairs on workload bridges";
            wantedBy = [ "multi-user.target" ];
            requires = [ "nftables.service" ];
            after = [ "nftables.service" ];
            unitConfig.ReloadPropagatedFrom = [ "nftables.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = lib.getExe refill;
              ExecReload = lib.getExe refill;
            };
          };

          services.workload-leases-refresh = {
            description = "Rebind leased MAC and address pairs after a lease change";
            after = [ "workload-leases.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe refill;
            };
          };

          paths.workload-leases-refresh = {
            description = "Watch workload DHCP leases";
            wantedBy = [ "paths.target" ];
            pathConfig.PathChanged = map statusOf (lib.attrValues networks);
          };
        };
      };
    };
in
{
  flake.nixosModules."workloads-vms" = leasesModule;
}
