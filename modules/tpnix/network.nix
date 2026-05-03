{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    let
      # Destinations that must skip the ProtonVPN tunnel and exit via the
      # local LAN gateway. Proton's policy-routing setup includes
      # `from all lookup main suppress_prefixlength 0`, so a /32 host route
      # planted in the main table wins over Proton's `default dev proton0`.
      vpnBypassHosts = [
        "66.9.145.15" # mail.deem.sa — origin drops ProtonVPN exit IPs
      ];

      vpnBypassDispatcher = pkgs.writeShellScript "vpn-bypass-dispatcher" ''
        # `set -o pipefail` is intentionally unset: the `ip ... | awk`
        # pipeline must produce an empty `gw` (and silent return) when an
        # interface has no IPv4 default route, rather than aborting the
        # dispatcher.
        set -eu
        IFACE="''${1:-}"
        ACTION="''${2:-}"

        log() { ${pkgs.util-linux}/bin/logger -t vpn-bypass "$*"; }

        case "$IFACE" in
          "" | lo | proton0 | tun* | wg* | tailscale*) exit 0 ;;
        esac

        addRoutes() {
          gw=$(${pkgs.iproute2}/bin/ip -4 -o route show default dev "$IFACE" \
            | ${pkgs.gawk}/bin/awk '/default via / {print $3; exit}')
          if [ -z "$gw" ]; then
            # Lease without a gateway: drop any previously-planted bypass
            # routes so traffic falls back to ProtonVPN instead of pointing
            # at a stale gateway.
            log "no gateway on $IFACE; clearing bypass routes"
            delRoutes
            return 0
          fi
          log "planting bypass routes on $IFACE via $gw (action=$ACTION)"
          ${lib.concatMapStringsSep "\n          " (host: ''
            ${pkgs.iproute2}/bin/ip route replace ${host}/32 via "$gw" dev "$IFACE"
          '') vpnBypassHosts}
        }

        delRoutes() {
          :
          ${lib.concatMapStringsSep "\n          " (host: ''
            ${pkgs.iproute2}/bin/ip route del ${host}/32 dev "$IFACE" 2>/dev/null || true
          '') vpnBypassHosts}
        }

        case "$ACTION" in
          up | dhcp4-change | dhcp6-change) addRoutes ;;
          down) log "removing bypass routes from $IFACE"; delRoutes ;;
        esac
      '';
    in
    {
      networking = {
        networkmanager = {
          enable = true;
          dispatcherScripts = [
            {
              source = vpnBypassDispatcher;
              type = "basic";
            }
          ];
        };
        useDHCP = lib.mkDefault true;
        firewall = {
          enable = true;
          allowedTCPPorts = [
            9999 # Stash default port
          ];
          # Allow SSH from the Tailscale tunnel
          interfaces.tailscale0.allowedTCPPorts = [ 22 ];

          # Allow SSH from local network (10.0.0.0/8)
          extraCommands = ''
            iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept
          '';
          extraStopCommands = ''
            iptables -D nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept || true
          '';
        };
      };
    };
}
