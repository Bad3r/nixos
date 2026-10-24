{ lib }:
name: network:
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
in
''
  <network>
    <name>${name}</name>
    <uuid>${libvirt.uuid}</uuid>
    <metadata>
      <wl:managed xmlns:wl="https://github.com/Bad3r/nixos/workloads"/>
    </metadata>
    <forward mode="open"/>
    <bridge name="${network.bridge}" stp="on" delay="0"/>
    <mac address="52:54:00:${mac}"/>
    <mtu size="${toString network.mtu}"/>
    <dns enable="${if network.egress == "none" then "no" else "yes"}"/>
    <ip address="${network.gateway}" prefix="24">
      <dhcp>
        <range start="${address libvirt.dhcp.start}" end="${address libvirt.dhcp.end}"/>
      </dhcp>
    </ip>
  </network>
''
