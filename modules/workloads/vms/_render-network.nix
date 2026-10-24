{ lib }:
name: network: hosts:
let
  inherit (network) libvirt;
  prefix = lib.removeSuffix ".0/24" network.subnet;
  address = offset: "${prefix}.${toString offset}";
  # libvirt draws a random bridge MAC at every define that omits one.
  macHash = builtins.hashString "sha256" "${libvirt.uuid}/bridge";
  mac = lib.concatMapStringsSep ":" (index: builtins.substring (2 * index) 2 macHash) [
    0
    1
    2
  ];
  # warp-svc's local resolvers; with forwarders set, dnsmasq ignores
  # /etc/resolv.conf, so guest lookups fail while WARP is down.
  dns =
    if network.egress == "none" then
      ''<dns enable="no"/>''
    else
      "<dns>"
      + lib.concatMapStrings (addr: "\n    <forwarder addr=\"${addr}\"/>") [
        "127.0.2.2"
        "127.0.2.3"
      ]
      + lib.concatStrings (
        lib.mapAttrsToList (
          ip: names:
          "\n    <host ip=\"${ip}\">"
          + lib.concatMapStrings (hostname: "<hostname>${hostname}</hostname>") names
          + "</host>"
        ) network.dnsHosts
      )
      + "\n  </dns>";
  # no-hosts keeps the host's /etc/hosts, Mesh names included, from guests;
  # local=/vm/ answers unknown .vm names instead of forwarding them.
in
''
  <network xmlns:dnsmasq="http://libvirt.org/schemas/network/dnsmasq/1.0">
    <name>${name}</name>
    <uuid>${libvirt.uuid}</uuid>
    <metadata>
      <wl:managed xmlns:wl="https://github.com/Bad3r/nixos/workloads"/>
    </metadata>
    <forward mode="open"/>
    <bridge name="${network.bridge}" stp="on" delay="0"/>
    <mac address="52:54:00:${mac}"/>
    <mtu size="${toString network.mtu}"/>
    ${dns}
    <ip address="${network.gateway}" prefix="24">
      <dhcp>
        <range start="${address libvirt.dhcp.start}" end="${address libvirt.dhcp.end}"/>
        ${lib.concatMapStrings (
          host: ''<host mac="${host.mac}" name="${host.name}" ip="${host.ip}"/>''
        ) hosts}
      </dhcp>
    </ip>
    <dnsmasq:options>
      <dnsmasq:option value="no-hosts"/>
      ${lib.optionalString (network.egress != "none") ''<dnsmasq:option value="local=/vm/"/>''}
    </dnsmasq:options>
  </network>
''
