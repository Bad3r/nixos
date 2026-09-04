# Coverage for the firewallDnsInterfaces classifier in
# modules/hosts/common/firewall.nix.
#
# A host with `firewallDnsInterfaces = [ ]` makes both assertions and the
# warning in that module vacuously true in its closure. Without this file a typo
# in one regex
# alternative, or an option silently dropped from the `declaredNames` sources,
# passes the whole suite.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/checks.nix).
#
# The interface names below are fixtures, not names any host carries. lan0 is
# the example systemd.link(5) gives for a safe pin, so it stands for the
# accepted case; eth0 and wlan0 stand for the rejected one. Swapping them would
# invert what each case asserts.
{ config, lib, ... }:
let
  classify = config.flake.lib.nixos._firewallDnsClassify or null;
  pinnedNamesOf = config.flake.lib.nixos._firewallDnsPinnedNamesOf or null;
  declaredNamesOf = config.flake.lib.nixos._firewallDnsDeclaredNamesOf or null;
  collidingPinsOf = config.flake.lib.nixos._firewallDnsCollidingPinsOf or null;
  duplicatePinsOf = config.flake.lib.nixos._firewallDnsDuplicatePinsOf or null;
  policyOverriddenPinsOf = config.flake.lib.nixos._firewallDnsPolicyOverriddenPinsOf or null;
  shadowedLinksOf = config.flake.lib.nixos._firewallDnsShadowedLinksOf or null;
  unboundLinksOf = config.flake.lib.nixos._firewallDnsUnboundLinksOf or null;
  defaultShadowedLinksOf = config.flake.lib.nixos._firewallDnsDefaultShadowedLinksOf or null;
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");

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

  # The shape modules/songbird/networking.nix and modules/system76/networking.nix
  # use: a binding match with no Name=, which displaces 99-default.link for the
  # device without renaming it. Both classifiers key on Name=, so this must read
  # as neither a pin nor a collision; every case above sets Name=, so nothing
  # else covers a link file that omits it.
  altnamesOnlyLink = {
    matchConfig.Path = "pci-0000:84:00.0";
    linkConfig = {
      NamePolicy = "keep kernel database onboard slot path";
      AlternativeNamesPolicy = "database onboard slot path";
    };
  };

  # A class match with no Name=, the shape a wake-on-LAN or MTU file takes:
  # unbound, but it renames nothing, so only its position can make it a hazard.
  broadLink = {
    matchConfig.Type = "ether";
    linkConfig.WakeOnLan = "magic";
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
    {
      name = "link without Name= is not a pin";
      links."10-altnames" = altnamesOnlyLink;
      expected = [ ];
    }
  ];

  duplicatePinCases = [
    {
      name = "distinct device pins cannot share a name";
      links = {
        "10-a" = link { Path = "pci-0000:84:00.0"; } "lan0";
        "20-b" = link { Path = "pci-0000:85:00.0"; } "lan0";
      };
      expected = [ "lan0" ];
    }
    {
      name = "distinct device pins may use distinct names";
      links = {
        "10-a" = link { Path = "pci-0000:84:00.0"; } "lan0";
        "20-b" = link { Path = "pci-0000:85:00.0"; } "lan1";
      };
      expected = [ ];
    }
    {
      name = "disabled duplicate pin is ignored";
      links = {
        "10-a" = (link { Path = "pci-0000:84:00.0"; } "lan0") // {
          enable = false;
        };
        "20-b" = link { Path = "pci-0000:85:00.0"; } "lan0";
      };
      expected = [ ];
    }
    {
      # Non-binding files are covered by unboundLinksOf instead. They do not
      # contribute a valid device-specific pin to this classifier.
      name = "unbound duplicate names are outside the pin classifier";
      links = {
        "10-a".linkConfig.Name = "lan0";
        "20-b".linkConfig.Name = "lan0";
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
        "mcp0s1"
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
        "mcp0s1"
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
      # A wired host with no .link binding eth0 to a device: it belongs in
      # kernelNames, so the warning fires.
      name = "unpinned wired kernel name under kernel naming";
      dnsInterfaces = [ "eth0" ];
      declaredNames = [ ];
      predictable = false;
      predictableNames = [ ];
      kernelNames = [ "eth0" ];
      unbackedNames = [ ];
      staleScheme = [ ];
    }
    {
      # The same name with a pin behind it. declaredNames is subtracted, so it
      # leaves kernelNames and the warning goes quiet, which is what makes the
      # warning actionable rather than permanent noise.
      name = "wired kernel name with a pin behind it";
      dnsInterfaces = [ "eth0" ];
      declaredNames = [ "eth0" ];
      predictable = false;
      predictableNames = [ ];
      kernelNames = [ ];
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

  # Shared by the six single-classifier case tables below: each compares one
  # classifier's output against one case's `expected` and names the mismatch.
  mkFailures =
    of: cases:
    lib.concatMap (
      case:
      let
        got = of case.links;
      in
      lib.optional (got != case.expected) "${case.name}: got ${fmt got}, expected ${fmt case.expected}"
    ) cases;

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

  pinnedFailures = mkFailures pinnedNamesOf pinnedCases;

  duplicatePinFailures = mkFailures duplicatePinsOf duplicatePinCases;

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
  # A pin and a policy in the same file. systemd.link(5) gives Name= the lower
  # precedence, so the policy wins and the pin does not apply. Wired hosts can
  # ship the no-Name= policy shape, so adding Name= there is the natural way to
  # satisfy the kernel-name warning and the one that silently does nothing.
  policyOverrideCases = [
    {
      name = "pin with no NamePolicy is accepted";
      links."10-lan0" = link { Path = "pci-0000:00:14.0-usb-0:1.4:1.0"; } "lan0";
      expected = [ ];
    }
    {
      name = "altname-narrowing file with no Name is accepted";
      links."10-altnames" = altnamesOnlyLink;
      expected = [ ];
    }
    {
      name = "Name added to the altname-narrowing file is rejected";
      links."10-altnames" = lib.recursiveUpdate altnamesOnlyLink { linkConfig.Name = "lan0"; };
      expected = [ "10-altnames" ];
    }
    {
      name = "disabled file carrying both is accepted";
      links."10-altnames" = lib.recursiveUpdate altnamesOnlyLink {
        enable = false;
        linkConfig.Name = "lan0";
      };
      expected = [ ];
    }
  ];

  # udev applies only the first matching file, so a second .link for a device
  # that already has one is never read, while pinnedNamesOf still reads its
  # Name= and reports the name as backed. Wired hosts commonly ship a .link
  # per NIC, so this is the shape the kernel-name warning invites.
  shadowedCases = [
    {
      name = "one file per device is accepted";
      links = {
        "10-a" = link { Path = "pci-0000:84:00.0"; } "lan0";
        "10-b" = link { Path = "pci-0000:85:00.0"; } "lan1";
      };
      expected = [ ];
    }
    {
      name = "a second file for the same device is rejected";
      links = {
        "10-realtek" = altnamesOnlyLink;
        "20-uplink" = link { Path = "pci-0000:84:00.0"; } "lan0";
      };
      expected = [ "Path=pci-0000:84:00.0" ];
    }
    {
      name = "a disabled second file is accepted";
      links = {
        "10-realtek" = altnamesOnlyLink;
        "20-uplink" = (link { Path = "pci-0000:84:00.0"; } "lan0") // {
          enable = false;
        };
      };
      expected = [ ];
    }
    {
      # Neither has a singleton device selector, so shadowedLinksOf does not
      # report a repeated selector. unboundLinksOf covers the earlier file.
      name = "two unbound files are not selector duplicates";
      links = {
        "10-a".linkConfig.Name = "lan0";
        "20-b".linkConfig.Name = "lan1";
      };
      expected = [ ];
    }
    {
      # The first file binds on the second key only; the second repeats it while
      # also carrying a Path=. Keying on the first bound key alone would read
      # these as two devices, which is the shape this guard exists to reject.
      name = "shared binding on a non-first key is rejected";
      links = {
        "10-a".matchConfig.PermanentMACAddress = "02:00:00:00:00:01";
        "20-b" = {
          matchConfig = {
            Path = "pci-0000:84:00.0";
            PermanentMACAddress = "02:00:00:00:00:01";
          };
          linkConfig.Name = "lan0";
        };
      };
      expected = [ "PermanentMACAddress=02:00:00:00:00:01" ];
    }
    {
      name = "same device matched by different keys is not counted";
      links = {
        "10-a" = link { Path = "pci-0000:84:00.0"; } "lan0";
        "20-b" = link { PermanentMACAddress = "02:00:00:00:00:01"; } "lan1";
      };
      expected = [ ];
    }
  ];

  unboundCases = [
    {
      name = "unbound file before a specific file is rejected";
      links = {
        "10-a".linkConfig.Name = "lan0";
        "20-b" = link { Path = "pci-0000:84:00.0"; } "lan1";
      };
      expected = [ "10-a" ];
    }
    {
      # Each applies to every device no earlier file matched and renames it, so
      # position does not excuse the later one.
      name = "two unbound files that pin a Name= are both rejected";
      links = {
        "10-a".linkConfig.Name = "lan0";
        "20-b".linkConfig.Name = "lan1";
      };
      expected = [
        "10-a"
        "20-b"
      ];
    }
    {
      name = "two unbound files without Name= report only the earlier unit";
      links = {
        "10-a" = broadLink;
        "20-b" = broadLink;
      };
      expected = [ "10-a" ];
    }
    {
      name = "wildcard OriginalName before a specific file is rejected";
      links = {
        "05-wol" = {
          matchConfig.OriginalName = "*";
          linkConfig.Name = "lan0";
        };
        "10-wifi0" = link { Path = "pci-0000:86:00.0"; } "wlan0";
      };
      expected = [ "05-wol" ];
    }
    {
      # The static classifier conservatively rejects a class-only match because
      # it cannot prove that the broad file will not shadow a later device pin.
      name = "class-only match before a specific file is rejected";
      links = {
        "05-ether" = {
          matchConfig.Type = "ether";
          linkConfig.Name = "lan0";
        };
        "10-wifi0" = link { Path = "pci-0000:86:00.0"; } "wlan0";
      };
      expected = [ "05-ether" ];
    }
    {
      name = "multi-valued selector before a specific file is rejected";
      links = {
        "05-a" = link { Path = "pci-0000:84:00.0 pci-0000:85:00.0"; } "lan0";
        "10-b" = link { Path = "pci-0000:86:00.0"; } "lan1";
      };
      expected = [ "05-a" ];
    }
    {
      name = "disabled broad file is accepted";
      links = {
        "05-wol" = {
          enable = false;
          matchConfig.OriginalName = "*";
          linkConfig.Name = "lan0";
        };
        "10-wifi0" = link { Path = "pci-0000:86:00.0"; } "wlan0";
      };
      expected = [ ];
    }
    {
      name = "broad file without Name= after a specific file is accepted";
      links = {
        "10-wifi0" = link { Path = "pci-0000:86:00.0"; } "wlan0";
        "20-wol" = broadLink;
      };
      expected = [ ];
    }
    {
      # Read after the specific file, but it still matches every other device
      # and renames each of them to lan0.
      name = "broad file that pins a Name= after a specific file is rejected";
      links = {
        "10-wifi0" = link { Path = "pci-0000:86:00.0"; } "wlan0";
        "20-wol".linkConfig.Name = "lan0";
      };
      expected = [ "20-wol" ];
    }
    {
      # "10-net-fallback.link" sorts before "10-net.link" under udev's strcmp
      # order even though the bare name sorts after: the broad file is read first.
      name = "broad file whose rendered name precedes a prefix name is rejected";
      links = {
        "10-net" = link { Path = "pci-0000:84:00.0"; } "lan0";
        "10-net-fallback" = broadLink;
      };
      expected = [ "10-net-fallback" ];
    }
    {
      name = "broad file whose rendered name follows a longer specific name is accepted";
      links = {
        "10-net" = broadLink;
        "10-net-fallback" = link { Path = "pci-0000:84:00.0"; } "lan1";
      };
      expected = [ ];
    }
  ];

  # udev reads systemd's 99-default.link (OriginalName=*) ahead of every
  # basename that sorts after it, so a host file there is never applied.
  defaultShadowedCases = [
    {
      name = "pin sorting after 99-default.link is rejected";
      links."99-uplink" = link { Path = "pci-0000:84:00.0"; } "lan0";
      expected = [ "99-uplink" ];
    }
    {
      name = "pin sorting before 99-default.link is accepted";
      links."10-realtek-5gbe" = link { Path = "pci-0000:84:00.0"; } "lan0";
      expected = [ ];
    }
    {
      # '-' sorts before '.', so 99-default-uplink.link is read before
      # 99-default.link even though the bare name sorts after 99-default.
      name = "pin whose rendered name precedes 99-default.link is accepted";
      links."99-default-uplink" = link { Path = "pci-0000:84:00.0"; } "lan0";
      expected = [ ];
    }
    {
      name = "pin whose rendered name extends 99-default.link is rejected";
      links."99-defaults" = link { Path = "pci-0000:84:00.0"; } "lan0";
      expected = [ "99-defaults" ];
    }
    {
      # /etc/systemd/network wins over /usr/lib/systemd/network for the same
      # basename, so this file replaces systemd's copy rather than hiding behind it.
      name = "host file named 99-default is accepted";
      links."99-default" = link { Path = "pci-0000:84:00.0"; } "lan0";
      expected = [ ];
    }
    {
      name = "disabled file sorting after 99-default.link is accepted";
      links."99-uplink" = {
        enable = false;
        matchConfig.Path = "pci-0000:84:00.0";
        linkConfig.Name = "lan0";
      };
      expected = [ ];
    }
    {
      # Nothing to count as declared, but the file is still dead: its altname
      # policy never applies either.
      name = "no-Name file sorting after 99-default.link is rejected";
      links."99-onboard" = altnamesOnlyLink;
      expected = [ "99-onboard" ];
    }
  ];

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
    {
      name = "link without Name= does not collide";
      links."10-altnames" = altnamesOnlyLink;
      expected = [ ];
    }
  ];

  collisionFailures = mkFailures collidingPinsOf collisionCases;

  policyOverrideFailures = mkFailures policyOverriddenPinsOf policyOverrideCases;

  shadowedFailures = mkFailures shadowedLinksOf shadowedCases;

  unboundFailures = mkFailures unboundLinksOf unboundCases;

  defaultShadowedFailures = mkFailures defaultShadowedLinksOf defaultShadowedCases;

  failures =
    classifyFailures
    ++ pinnedFailures
    ++ duplicatePinFailures
    ++ declaredFailures
    ++ networkdOffFailures
    ++ collisionFailures
    ++ policyOverrideFailures
    ++ shadowedFailures
    ++ unboundFailures
    ++ defaultShadowedFailures;

  missingExports =
    classify == null
    || pinnedNamesOf == null
    || declaredNamesOf == null
    || collidingPinsOf == null
    || duplicatePinsOf == null
    || policyOverriddenPinsOf == null
    || shadowedLinksOf == null
    || unboundLinksOf == null
    || defaultShadowedLinksOf == null;
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
            + "_firewallDnsDeclaredNamesOf, _firewallDnsCollidingPinsOf, "
            + "_firewallDnsDuplicatePinsOf, _firewallDnsPolicyOverriddenPinsOf, "
            + "_firewallDnsShadowedLinksOf, _firewallDnsUnboundLinksOf, and "
            + "_firewallDnsDefaultShadowedLinksOf, so the firewallDnsInterfaces guards are "
            + "unverified."
          )
        else if failures != [ ] then
          throw (formatCaseFailures "firewall-dns-interface-classifier" failures)
        else
          pkgs.runCommandLocal "firewall-dns-interface-classifier-ok" { } ''
            echo "ok: ${
              toString (
                lib.length classifyCases
                + lib.length pinnedCases
                + lib.length duplicatePinCases
                + lib.length collisionCases
                + lib.length policyOverrideCases
                + lib.length shadowedCases
                + lib.length unboundCases
                + lib.length defaultShadowedCases
                + 2
              )
            } classifier cases" > $out
          '';
    };
}
