# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
#   flake.lib.nixos.hosts.<host>.firewallLocalTcpPortRanges
#     Additional TCP port ranges open from 10.0.0.0/8, from 192.168.0.0/16,
#     and on the CloudflareWARP interface.
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  localNetworkCidrs = [
    "10.0.0.0/8"
    "192.168.0.0/16"
  ];
  meshInterface = "CloudflareWARP";

  # Restores what 99-default.link supplies minus its "mac" altname token.
  stableNamePolicyLinkConfig = {
    NamePolicy = "keep kernel database onboard slot path";
    AlternativeNamesPolicy = "database onboard slot path";
  };

  body =
    { hostName, lib, ... }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
      extraTcpPortRanges = hostFlags.firewallExtraTcpPortRanges or [ ];
      localTcpPortRanges = hostFlags.firewallLocalTcpPortRanges or [ ];
      localTcpPorts = lib.concatStringsSep ", " (
        [ "22" ] ++ map (range: "${toString range.from}-${toString range.to}") localTcpPortRanges
      );
    in
    {
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          9999 # Stash default port
        ];
        allowedTCPPortRanges = extraTcpPortRanges;
        interfaces = {
          tailscale0.allowedTCPPorts = [ 22 ];
          # Inert until the device profile routes the Mesh allocation into the tunnel:
          # the stock split-tunnel exclude list covers all of 100.64.0.0/10, so
          # the profile excludes 100.64.0.0/11 and 100.112.0.0/12 instead of
          # dropping the CGNAT entry, which carves out the Mesh allocation and keeps
          # any tailnet address in 100.112.0.0/12 excluded.
          # Mesh is the private network once the tailnet retires, so the
          # developer ranges ride it and Mesh peers reach the LAN-only dev
          # servers; tailscale0 above stays SSH-only for a host that opts back in.
          # The interface is the scope: every device enrolled in the team reaches
          # the ranges, accepted over per-peer source rules, which would close the
          # ports until each address is recorded and on every re-registration.
          ${meshInterface} = {
            allowedTCPPorts = [ 22 ];
            allowedTCPPortRanges = localTcpPortRanges;
          };
        };
        extraInputRules = "ip saddr { ${lib.concatStringsSep ", " localNetworkCidrs} } tcp dport { ${localTcpPorts} } accept";
      };
      networking.nftables = {
        enable = true;
        # Keeps warp-svc's table and every other daemon's across reloads.
        flushRuleset = false;
      };
    };
in
{
  flake = {
    lib.nixos = {
      _firewallLocalNetworkCidrs = localNetworkCidrs;
      _firewallMeshInterface = meshInterface;
      _firewallStableNamePolicyLinkConfig = stableNamePolicyLinkConfig;
    };
    nixosModules.hosts-common.imports = [ body ];
  };
}
