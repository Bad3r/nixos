# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallDnsInterfaces
#     Interfaces allowed to serve DNS/DHCP (UDP 53/67, TCP 53).
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  body =
    {
      hostName,
      config,
      lib,
      ...
    }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
      dnsInterfaces = hostFlags.firewallDnsInterfaces or [ ];
      extraTcpPortRanges = hostFlags.firewallExtraTcpPortRanges or [ ];
      # enp4s0, eno1, ens3, enx001122334455, wlp0s20f3; not eth0 or wlan0.
      predictableNames = lib.filter (n: lib.match "(en|wl)[posx].*" n != null) dnsInterfaces;
      # eth0, wlan0; not a .link-pinned name such as lan0, nor tailscale0.
      kernelNames = lib.filter (n: lib.match "(eth|wlan)[0-9]+" n != null) dnsInterfaces;
      predictable = config.networking.usePredictableInterfaceNames;
      # Names a .link Name= creates on this host, such as lan0.
      pinnedNames = lib.filter (n: n != null) (
        lib.mapAttrsToList (_: link: link.linkConfig.Name or null) config.systemd.network.links
      );
      # Neither naming scheme produces these, so only a .link Name= can.
      unbackedNames = lib.filter (
        n: !(lib.elem n predictableNames || lib.elem n kernelNames || lib.elem n pinnedNames)
      ) dnsInterfaces;
    in
    {
      # A name that matches no device is not an evaluation error on its own:
      # genAttrs below still emits an interfaces entry, so the opening silently
      # does nothing. Both naming schemes are reachable, so guard both.
      assertions = [
        {
          assertion = predictable || predictableNames == [ ];
          message =
            "${hostName}: firewallDnsInterfaces has predictable interface names "
            + "(${lib.concatStringsSep ", " predictableNames}) but the host boots with "
            + "net.ifnames=0, so they match no device. Use the kernel name (eth0, wlan0) "
            + "read from `ip -br link` after the first boot on this configuration.";
        }
        {
          assertion = !predictable || kernelNames == [ ];
          message =
            "${hostName}: firewallDnsInterfaces has kernel interface names "
            + "(${lib.concatStringsSep ", " kernelNames}) but the host sets "
            + "networking.usePredictableInterfaceNames = true, so they match no device. "
            + "Use the predictable name, or pin the device with a .link Name= outside the "
            + "eth*/wlan* namespace as modules/system76/networking.nix does.";
        }
        {
          assertion = unbackedNames == [ ];
          message =
            "${hostName}: firewallDnsInterfaces names "
            + "(${lib.concatStringsSep ", " unbackedNames}) are neither predictable nor "
            + "kernel-assigned, and no systemd.network.links entry sets linkConfig.Name to "
            + "them, so they match no device. Add the .link pin as "
            + "modules/system76/networking.nix does.";
        }
      ];

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          9999 # Stash default port
        ];
        allowedTCPPortRanges = extraTcpPortRanges;
        interfaces = {
          tailscale0.allowedTCPPorts = [ 22 ];
        }
        // lib.genAttrs dnsInterfaces (_: {
          allowedUDPPorts = [
            53
            67
          ];
          allowedTCPPorts = [ 53 ];
        });
        # Allow SSH from local network (10.0.0.0/8)
        extraCommands = ''
          iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept
        '';
        extraStopCommands = ''
          iptables -D nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept || true
        '';
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
