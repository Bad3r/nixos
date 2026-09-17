# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
#   flake.lib.nixos.hosts.<host>.firewallLocalTcpPortRanges
#     Additional TCP port ranges open from 10.0.0.0/8 and 192.168.0.0/16 IPv4 sources.
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  localNetworkCidrs = [
    "10.0.0.0/8"
    "192.168.0.0/16"
  ];

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
      localTcpPortRangeCommands = lib.concatMapStrings (
        range:
        let
          portRange = "${toString range.from}:${toString range.to}";
        in
        lib.concatMapStrings (
          cidr: "iptables -A nixos-fw -s ${cidr} -p tcp --dport ${portRange} -j nixos-fw-accept\n"
        ) localNetworkCidrs
      ) localTcpPortRanges;
    in
    {
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          9999 # Stash default port
        ];
        allowedTCPPortRanges = extraTcpPortRanges;
        interfaces.tailscale0.allowedTCPPorts = [ 22 ];
        # Allow SSH from local network (10.0.0.0/8)
        extraCommands = ''
          iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept
          ${localTcpPortRangeCommands}
        '';
      };
    };
in
{
  flake = {
    lib.nixos = {
      _firewallLocalNetworkCidrs = localNetworkCidrs;
      _firewallStableNamePolicyLinkConfig = stableNamePolicyLinkConfig;
    };
    nixosModules.hosts-common.imports = [ body ];
  };
}
