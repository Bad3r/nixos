# Coverage for the firewallDnsInterfaces classifier in
# modules/hosts/common/firewall.nix.
#
# Every host currently sets `firewallDnsInterfaces = [ ]`, so both assertions
# and the warning in that module are vacuously true in every host closure
# `nix flake check` evaluates. Without this file a typo in one regex
# alternative, or an option silently dropped from the `declaredNames` sources,
# passes the whole suite.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/checks.nix).
{ config, lib, ... }:
let
  classify = config.flake.lib.nixos._firewallDnsClassify or null;
  pinnedNamesOf = config.flake.lib.nixos._firewallDnsPinnedNamesOf or null;
  declaredNamesOf = config.flake.lib.nixos._firewallDnsDeclaredNamesOf or null;
  collidingPinsOf = config.flake.lib.nixos._firewallDnsCollidingPinsOf or null;

  # One entry per source declaredNamesOf reads. A source dropped from that
  # expression loses its name here, which is the failure this covers.
  declaredStub = {
    systemd.network = {
      enable = true;
      links."10-lan0" = link { Path = "pci-0000:00:14.0-usb-0:1.4:1.0"; } "lan0";
      netdevs = {
        "10-vx0".netdevConfig.Name = "vx0";
        "10-off0" = {
          enable = false;
          netdevConfig.Name = "off0";
        };
        # Keyed by unit basename, so a netdev without netdevConfig.Name must
        # contribute nothing rather than its key.
        "eth0".netdevConfig = { };
      };
    };
    networking = {
      bridges."br0" = { };
      bonds."bond0" = { };
      vlans."vlan0" = { };
      macvlans."macvlan0" = { };
      ipvlans."ipvlan0" = { };
      vswitches."ovs0" = { };
      wlanInterfaces."wlan-ap0" = { };
      sits."sit0" = { };
      greTunnels."gre0" = { };
      wireguard.interfaces."wg0" = { };
      wg-quick.interfaces."wgq0" = { };
    };
  };

  declaredExpected = [
    "lan0"
    "br0"
    "bond0"
    "vlan0"
    "macvlan0"
    "ipvlan0"
    "ovs0"
    "wlan-ap0"
    "sit0"
    "gre0"
    "wg0"
    "wgq0"
    "vx0"
  ];

  # Names present in the stub that must not come back.
  declaredRejected = [
    "off0"
    "eth0"
  ];

  # Same stub with networkd off: a netdev is created by systemd-networkd, so no
  # netdev name exists there. The .link pin still does, since udev honors .link
  # files either way.
  networkdOffStub = lib.recursiveUpdate declaredStub { systemd.network.enable = false; };
  networkdOffExpected = [ "lan0" ];
  networkdOffRejected = [
    "vx0"
    "off0"
    "eth0"
  ];

  link = matchConfig: name: {
    inherit matchConfig;
    linkConfig.Name = name;
  };

  pinnedCases = [
    {
      name = "path-matched link is a pin";
      links."10-lan0" = link { Path = "pci-0000:00:14.0-usb-0:1.4:1.0"; } "lan0";
      expected = [ "lan0" ];
    }
    {
      # Matches the current address, which the "stable" policy replaces.
      name = "MACAddress selects a mutable address, not a device";
      links."10-lan0" = link { MACAddress = "02:00:00:00:00:01"; } "lan0";
      expected = [ ];
    }
    {
      name = "PermanentMACAddress-matched link is a pin";
      links."10-lan0" = link { PermanentMACAddress = "02:00:00:00:00:01"; } "lan0";
      expected = [ "lan0" ];
    }
    {
      name = "Property selects a class, not a device";
      links."10-lan0" = link { Property = "ID_BUS=usb"; } "lan0";
      expected = [ ];
    }
    {
      name = "empty selector value is not a pin";
      links."10-lan0" = link { Path = ""; } "lan0";
      expected = [ ];
    }
    {
      name = "tab-separated values are not a pin";
      links."10-lan0" = link { Path = "pci-0000:00:14.3\tpci-0000:04:00.0"; } "lan0";
      expected = [ ];
    }
    {
      name = "link with an empty match is not a pin";
      links."10-lan0" = link { } "lan0";
      expected = [ ];
    }
    {
      name = "wildcard OriginalName is not a pin";
      links."10-lan0" = link { OriginalName = "*"; } "lan0";
      expected = [ ];
    }
    {
      name = "class-only match is not a pin";
      links."10-lan0" = link { Type = "ether"; } "lan0";
      expected = [ ];
    }
    {
      name = "OriginalName never binds a device";
      links."10-lan0" = link { OriginalName = "enp4s0"; } "lan0";
      expected = [ ];
    }
    {
      name = "glob metacharacters are not a pin";
      links."10-lan0" = link { Path = "pci-0000:00:14.?"; } "lan0";
      expected = [ ];
    }
    {
      name = "inverted selector is not a pin";
      links."10-lan0" = link { Path = "!pci-0000:00:14.3"; } "lan0";
      expected = [ ];
    }
    {
      name = "bracket glob is not a pin";
      links."10-lan0" = link { Path = "pci-0000:00:14.[0-9]"; } "lan0";
      expected = [ ];
    }
    {
      name = "multi-value list is not a pin";
      links."10-lan0" = link {
        Path = [
          "pci-0000:00:14.3"
          "pci-0000:04:00.0"
        ];
      } "lan0";
      expected = [ ];
    }
    {
      name = "whitespace-separated values are not a pin";
      links."10-lan0" = link { Path = "pci-0000:00:14.3 pci-0000:04:00.0"; } "lan0";
      expected = [ ];
    }
    {
      name = "disabled link is not a pin";
      links."10-lan0" = (link { Path = "pci-0000:00:14.3"; } "lan0") // {
        enable = false;
      };
      expected = [ ];
    }
  ];

  # Each case names the classifier output list it belongs in, or "clean" when a
  # value is accepted without landing in any of them.
  classifyCases = [
    {
      name = "predictable name under kernel naming";
      dnsInterfaces = [ "wlp0s20f3" ];
      declaredNames = [ ];
      predictableNames = [ "wlp0s20f3" ];
      kernelNames = [ ];
      unbackedNames = [ ];
    }
    {
      name = "wwan, infiniband, and nonzero-PCI-domain predictable prefixes";
      dnsInterfaces = [
        "wwp0s20f0u2"
        "ibp5s0"
        "enP2p1s0"
        "eno1"
        "ens3"
        "enx001122334455"
        "enxb827ebaabbcc"
        "wlxb827ebaabbcc"
        "slp0s1"
        "enacmei1"
      ];
      declaredNames = [ ];
      predictableNames = [
        "wwp0s20f0u2"
        "ibp5s0"
        "enP2p1s0"
        "eno1"
        "ens3"
        "enx001122334455"
        "enxb827ebaabbcc"
        "wlxb827ebaabbcc"
        "slp0s1"
        "enacmei1"
      ];
      kernelNames = [ ];
      unbackedNames = [ ];
    }
    {
      name = "kernel name under predictable naming";
      dnsInterfaces = [ "wlan0" ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [ "wlan0" ];
      unbackedNames = [ ];
    }
    {
      name = "usbnet default name is kernel-assigned";
      dnsInterfaces = [
        "usb0"
        "wwan0"
        "ib0"
        "sl0"
      ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [
        "usb0"
        "wwan0"
        "ib0"
        "sl0"
      ];
      unbackedNames = [ ];
    }
    {
      name = "declared name is exempt from both scheme lists";
      dnsInterfaces = [ "wlan0" ];
      declaredNames = [ "wlan0" ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ ];
    }
    {
      name = "pinned name is backed";
      dnsInterfaces = [ "lan0" ];
      declaredNames = [ "lan0" ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ ];
    }
    {
      name = "pinned name without a pin is unbacked";
      dnsInterfaces = [ "lan0" ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ "lan0" ];
    }
    {
      name = "declared bridge is backed";
      dnsInterfaces = [ "br0" ];
      declaredNames = [ "br0" ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ ];
    }
    {
      name = "undeclared bridge is unbacked";
      dnsInterfaces = [ "br0" ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ "br0" ];
    }
    {
      name = "runtime interface warns rather than matching a scheme";
      dnsInterfaces = [ "tailscale0" ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ "tailscale0" ];
    }
    {
      name = "kernel name is stale under predictable naming";
      dnsInterfaces = [ "wlan0" ];
      declaredNames = [ ];
      predictable = true;
      predictableNames = [ ];
      kernelNames = [ "wlan0" ];
      unbackedNames = [ ];
      staleScheme = [ "wlan0" ];
    }
    {
      name = "kernel name is current under kernel naming";
      dnsInterfaces = [ "wlan0" ];
      declaredNames = [ ];
      predictable = false;
      predictableNames = [ ];
      kernelNames = [ "wlan0" ];
      unbackedNames = [ ];
      staleScheme = [ ];
    }
    {
      name = "predictable name is stale under kernel naming";
      dnsInterfaces = [ "wlp0s20f3" ];
      declaredNames = [ ];
      predictable = false;
      predictableNames = [ "wlp0s20f3" ];
      kernelNames = [ ];
      unbackedNames = [ ];
      staleScheme = [ "wlp0s20f3" ];
    }
    {
      name = "predictable name is current under predictable naming";
      dnsInterfaces = [ "wlp0s20f3" ];
      declaredNames = [ ];
      predictable = true;
      predictableNames = [ "wlp0s20f3" ];
      kernelNames = [ ];
      unbackedNames = [ ];
      staleScheme = [ ];
    }
    {
      name = "empty input stays empty";
      dnsInterfaces = [ ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ ];
      staleScheme = [ ];
    }
  ];

  fmt = names: "[ ${lib.concatStringsSep " " names} ]";

  classifyFailures = lib.concatMap (
    case:
    let
      got = classify {
        inherit (case) dnsInterfaces declaredNames;
        predictable = case.predictable or false;
      };
      mismatch =
        field:
        lib.optional (
          got.${field} != case.${field}
        ) "${case.name}: ${field} = ${fmt got.${field}}, expected ${fmt case.${field}}";
    in
    mismatch "predictableNames"
    ++ mismatch "kernelNames"
    ++ mismatch "unbackedNames"
    ++ lib.optionals (case ? staleScheme) (mismatch "staleScheme")
  ) classifyCases;

  pinnedFailures = lib.concatMap (
    case:
    let
      got = pinnedNamesOf case.links;
    in
    lib.optional (got != case.expected) "${case.name}: got ${fmt got}, expected ${fmt case.expected}"
  ) pinnedCases;

  declaredFailures =
    let
      got = declaredNamesOf declaredStub;
      missing = lib.subtractLists got declaredExpected;
      # A disabled unit writes nothing, so its name must not count as declared.
      counted = lib.filter (n: lib.elem n got) declaredRejected;
    in
    lib.optional (
      missing != [ ]
    ) "declaredNamesOf drops ${fmt missing}: a source was removed from the expression in firewall.nix"
    ++
      lib.optional (counted != [ ])
        "declaredNamesOf counts ${fmt counted}: a disabled unit is never installed, so it creates no interface";

  networkdOffFailures =
    let
      got = declaredNamesOf networkdOffStub;
      missing = lib.subtractLists got networkdOffExpected;
      counted = lib.filter (n: lib.elem n got) networkdOffRejected;
    in
    lib.optional (missing != [ ])
      "declaredNamesOf drops ${fmt missing} with networkd off: .link pins are honored by udev either way"
    ++
      lib.optional (counted != [ ])
        "declaredNamesOf counts ${fmt counted} with networkd off: a netdev is created by systemd-networkd";

  # A pin into a namespace the kernel assigns itself races udev, so it must be
  # rejected; a pin outside them must not be.
  collisionCases = [
    {
      name = "pin outside the kernel namespaces is accepted";
      links."10-lan0" = link { Path = "pci-0000:00:14.0-usb-0:1.4:1.0"; } "lan0";
      expected = [ ];
    }
    {
      name = "pin named eth0 collides";
      links."10-eth0" = link { Path = "pci-0000:04:00.0"; } "eth0";
      expected = [ "eth0" ];
    }
    {
      name = "pin named wlan0 collides";
      links."10-wlan0" = link { Path = "pci-0000:00:14.3"; } "wlan0";
      expected = [ "wlan0" ];
    }
    {
      name = "match-all link named eth0 collides";
      links."10-eth0".linkConfig.Name = "eth0";
      expected = [ "eth0" ];
    }
    {
      name = "disabled link named eth0 does not collide";
      links."10-eth0" = {
        enable = false;
        linkConfig.Name = "eth0";
      };
      expected = [ ];
    }
    {
      name = "pin named usb0 collides";
      links."10-usb0" = link { Path = "pci-0000:00:14.0-usb-0:1.4:1.0"; } "usb0";
      expected = [ "usb0" ];
    }
  ];

  collisionFailures = lib.concatMap (
    case:
    let
      got = collidingPinsOf case.links;
    in
    lib.optional (got != case.expected) "${case.name}: got ${fmt got}, expected ${fmt case.expected}"
  ) collisionCases;

  failures =
    classifyFailures ++ pinnedFailures ++ declaredFailures ++ networkdOffFailures ++ collisionFailures;

  missingExports =
    classify == null || pinnedNamesOf == null || declaredNamesOf == null || collidingPinsOf == null;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.firewall-dns-interface-classifier =
        if missingExports then
          throw (
            "firewall-dns-interface-classifier: modules/hosts/common/firewall.nix no longer exports "
            + "flake.lib.nixos._firewallDnsClassify, _firewallDnsPinnedNamesOf, "
            + "_firewallDnsDeclaredNamesOf, and _firewallDnsCollidingPinsOf, so the "
            + "firewallDnsInterfaces guards are unverified."
          )
        else if failures != [ ] then
          throw (
            "firewall-dns-interface-classifier: "
            + toString (lib.length failures)
            + " case(s) failed:\n  "
            + lib.concatStringsSep "\n  " failures
          )
        else
          pkgs.runCommandLocal "firewall-dns-interface-classifier-ok" { } ''
            echo "ok: ${
              toString (lib.length classifyCases + lib.length pinnedCases + lib.length collisionCases + 2)
            } classifier cases" > $out
          '';
    };
}
