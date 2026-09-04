# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallDnsInterfaces
#     Interfaces allowed to serve DNS/DHCP (UDP 53/67, TCP 53).
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
#   flake.lib.nixos.hosts.<host>.firewallLocalTcpPortRanges
#     Additional TCP port ranges open from 10.0.0.0/8 and 192.168.0.0/16 IPv4 sources.
{ config, lib, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  localNetworkCidrs = [
    "10.0.0.0/8"
    "192.168.0.0/16"
  ];

  # Restores what 99-default.link supplies minus its "mac" altname token.
  # Exported because the per-host .link entries that displace that file must
  # all carry the same pair; firewall-checks.nix keeps its own literal on
  # purpose, so the fixture cannot pass by agreeing with itself.
  stableNamePolicyLinkConfig = {
    NamePolicy = "keep kernel database onboard slot path";
    AlternativeNamesPolicy = "database onboard slot path";
  };

  # Bound once each: the classifier outputs stay mutually consistent only while
  # both patterns are single-sourced.
  # enp4s0, eno1, ens3, wlp0s20f3, wwp0s20f0u2, ibp5s0, and the enP2p1s0 form
  # systemd.net-naming-scheme(7) emits as prefix[Pdomain]sslot when the PCI
  # domain is not 0. Prefixes are the full table from that page: en, wl, ww, ib,
  # sl, mc. Two forms need their own branch because the character after the
  # letter is not a digit: the platform/ACPI a<vendor><model>i<instance> name,
  # whose vendor part is lowercase letters, and x<MAC>, whose 12 hex digits can
  # begin with a-f. The letter-then-digit shape keeps the classes disjoint:
  # wlan0 is wl + a + n and ib0 has no letter after the prefix, so both stay
  # kernel-assigned.
  predictableRe = "(en|wl|ww|ib|sl|mc)(P[0-9]+)?([abcdiopsv][0-9].*|a[a-z][a-z0-9]*i[0-9]+|x[0-9a-f]{12})";
  # Kernel-assigned. usb0 is the usbnet default: drivers/net/usb/usbnet.c only
  # switches to eth%d, wlan%d, or wwan%d for drivers flagged FLAG_ETHER,
  # FLAG_WLAN, or FLAG_WWAN, so a cdc_ether tether comes up as usb0.
  kernelRe = "(eth|wlan|usb|wwan|ib|sl)[0-9]+";
  matches = re: n: lib.match re n != null;

  # Pure classifier, exported so modules/hosts/common/firewall-checks.nix can
  # exercise every branch: every host leaves firewallDnsInterfaces empty, so
  # nothing in a host closure reaches these cases.
  classify =
    {
      dnsInterfaces,
      declaredNames,
      predictable,
    }:
    let
      # Both scheme lists subtract declaredNames: a name this host creates, such
      # as a .link pin or a wlanInterfaces AP, exists whichever scheme the host
      # boots with, so its shape says nothing about whether it is stale.
      predictableNames = lib.subtractLists declaredNames (
        lib.filter (matches predictableRe) dnsInterfaces
      );
      kernelNames = lib.subtractLists declaredNames (lib.filter (matches kernelRe) dnsInterfaces);
    in
    {
      inherit predictableNames kernelNames;
      unbackedNames = lib.filter (
        n: !(matches predictableRe n || matches kernelRe n || lib.elem n declaredNames)
      ) dnsInterfaces;
      # The scheme the host does not boot with, so these names match no device.
      # Selected here rather than in the assertion so the check table covers the
      # choice: a host policy with an empty dnsInterfaces would make an inverted
      # guard green in every closure.
      staleScheme = if predictable then kernelNames else predictableNames;
    };

  # Match keys that can bind a .link to one device. Type=, Driver=, and Property=
  # select a class, not a device (Property=ID_BUS=usb matches every USB netdev,
  # and the device-binding Property=ID_PATH= form is what Path= matches).
  # MACAddress= is absent for a reason specific to this repository: it matches
  # the device's current address, which is why PermanentMACAddress= exists
  # separately, and the "stable" policy above replaces that current address on
  # the first activation. A .link matched on it then binds nothing the next time
  # udev re-evaluates the device.
  # OriginalName= is excluded under either naming scheme: it matches the udev
  # INTERFACE property, and systemd.link(5) notes it "cannot be used to match on
  # names that have already been changed from userspace". The predictable rename
  # is done by the same net_setup_link builtin that applies these files, so the
  # device still carries its kernel name at match time; an enp*/wlp* value never
  # matches, and the eth0/wlan0 values that do are the discovery-order names the
  # same page calls "unstable between reboots".
  bindingMatchKeys = [
    "Path"
    "PermanentMACAddress"
  ];

  # Split on any whitespace run, not just spaces: systemd.link(5) calls these
  # "whitespace-separated" lists, and a tab or newline in a Nix multi-line
  # string separates values just as well. builtins.split drops empty tokens,
  # which also covers the empty assignment that resets the list.
  tokensOf =
    value:
    lib.filter (t: lib.isString t && t != "") (
      lib.concatMap (builtins.split "[[:space:]]+") (lib.toList value)
    );

  # A [Match] that is empty, whose selector is a glob, or which carries more than
  # one value matches each device udev initializes: it renames whichever
  # interface appears first and shadows every higher-numbered .link file, so it
  # does not bind a name. systemd.link(5) selectors are "a whitespace-separated
  # list of shell-style globs", so both the list and the glob forms are checked.
  bindsOneValue =
    value:
    let
      tokens = tokensOf value;
    in
    lib.length tokens == 1
    # A "!" prefix inverts the test, so the file applies to every device except
    # the one named: the match-all case again.
    && !(lib.hasPrefix "!" (lib.head tokens))
    && !(lib.any (c: lib.hasInfix c (lib.head tokens)) [
      "*"
      "?"
      "["
    ]);

  # A match key that is present on matchConfig and carries exactly one
  # non-glob value: the shape selectorsOf below turns into a device selector.
  isBoundKey = matchConfig: key: matchConfig ? ${key} && bindsOneValue matchConfig.${key};

  # Labels for the singleton selectors that identify one device. An empty list
  # means the file is broad or unbound in the static model below.
  selectorsOf =
    link:
    let
      matchConfig = link.matchConfig or { };
      bound = lib.filter (isBoundKey matchConfig) bindingMatchKeys;
    in
    map (key: "${key}=${lib.head (tokensOf matchConfig.${key})}") bound;

  # Resolves each link once; every list below is derived from this record set,
  # so the six link guards cannot disagree about what a link binds or pins.
  classifyLinks =
    links:
    let
      records = lib.mapAttrsToList (key: link: {
        inherit key;
        enabled = link.enable or true;
        linkName = link.linkConfig.Name or null;
        hasPolicy = (link.linkConfig or { }) ? Name && (link.linkConfig or { }) ? NamePolicy;
        selectors = selectorsOf link;
      }) links;
      enabledRecords = lib.filter (r: r.enabled) records;

      # Names a .link Name= creates on a host, such as wifi0. A disabled unit is
      # never installed and a match-all file does not bind a name to a device, so
      # neither counts as a pin.
      pinnedNames = lib.filter (n: n != null) (
        map (r: if r.selectors != [ ] then r.linkName else null) enabledRecords
      );

      shadowedSelectors = lib.concatMap (r: r.selectors) enabledRecords;

      enabledNames = map (r: r.key) enabledRecords;
      # udev sorts the rendered basenames with strcmp, so "10-net-fallback.link"
      # precedes "10-net.link" ('-' < '.') while the bare names order the other way.
      precedesAnother = name: lib.any (other: "${other}.link" > "${name}.link") enabledNames;
    in
    {
      inherit pinnedNames;

      # Pins into a namespace the kernel assigns itself. systemd.link(5) on Name=:
      # "specifying a name that the kernel might use for another interface (for
      # example eth0) is dangerous because the name assignment done by udev will
      # race with the assignment done by the kernel ... making the naming
      # unpredictable". A pin that loses that race leaves the device on its kernel
      # name, so anything keyed to the pinned name matches nothing.
      # Derived from every enabled link rather than from pinnedNames: a collision
      # is a property of the name a .link writes, not of whether it binds to one
      # device. A match-all file named eth0 is the worse case, not an excluded one.
      collidingPins = lib.filter (matches kernelRe) (
        lib.filter (n: n != null) (map (r: r.linkName) enabledRecords)
      );

      # Two enabled device-specific files cannot safely create the same interface
      # name. One rename wins, while declaredNamesFrom would otherwise treat the
      # duplicate as backed even when one of the pins does not produce the
      # intended interface name.
      duplicatePins = lib.unique (
        lib.filter (name: lib.count (other: other == name) pinnedNames > 1) pinnedNames
      );

      # Files that pin a name and also carry a policy that outranks it.
      # systemd.link(5) gives Name= the lower precedence of the two, so the policy
      # wins and the pin silently does not apply. Altname-narrowing files carry
      # NamePolicy= and no Name=, which is the shape that needs it, so
      # adding a Name= there is the natural way to satisfy the kernel-name warning
      # and the one that does not work. Keyed on both keys rather than on Name=
      # alone, which is what pinnedNames and collidingPins read, so neither of
      # them can see this.
      policyOverriddenPins = map (r: r.key) (lib.filter (r: r.hasPolicy) enabledRecords);

      # Enabled .link units that bind the same device by the same selector. udev
      # applies only the first matching file, so every later one is discarded, but
      # pinnedNames reads Name= off all of them. The shadowed name would otherwise
      # enter declaredNames and hide a firewall opening for a name that matches no
      # device. Wired hosts commonly ship a .link for each NIC, so that is the
      # shape the kernel-name warning invites.
      shadowedLinks = lib.unique (
        lib.filter (s: lib.count (x: x == s) shadowedSelectors > 1) shadowedSelectors
      );

      # An enabled file without a singleton device-binding selector applies to
      # every device no earlier file matched. One that pins a Name= renames all
      # of them to that name whatever its position, so it is reported
      # unconditionally; one without a Name= is a hazard only when it precedes
      # another file, whose device it can match first and shadow. This
      # deliberately includes broad class or name matches: the static model
      # cannot prove that one will not shadow a later file for another device
      # class.
      unboundLinks = map (r: r.key) (
        lib.filter (r: r.selectors == [ ] && (r.linkName != null || precedesAnother r.key)) enabledRecords
      );

      # Enabled files that sort after systemd's own 99-default.link. udev merges
      # /etc/systemd/network with /usr/lib/systemd/network by basename,
      # strcmp-sorts the result and applies the first match, and 99-default.link
      # matches every device (OriginalName=*), so such a file is never read while
      # pinnedNames still counts its Name= as declared. A host file named
      # 99-default itself replaces systemd's copy, so it is not reported.
      defaultShadowedLinks = lib.filter (name: "${name}.link" > "99-default.link") enabledNames;
    };

  # Per-field entry points for firewall-checks.nix and the flake.lib.nixos
  # exports below; the host body reads the classifyLinks result directly.
  pinnedNamesOf = links: (classifyLinks links).pinnedNames;
  collidingPinsOf = links: (classifyLinks links).collidingPins;
  duplicatePinsOf = links: (classifyLinks links).duplicatePins;
  policyOverriddenPinsOf = links: (classifyLinks links).policyOverriddenPins;
  shadowedLinksOf = links: (classifyLinks links).shadowedLinks;
  unboundLinksOf = links: (classifyLinks links).unboundLinks;
  defaultShadowedLinksOf = links: (classifyLinks links).defaultShadowedLinks;

  # Interfaces a host declares rather than inherits from a NIC. Exported with
  # the classifier so the check can assert every source is still read. Takes
  # pinnedNames as an argument so the host body can pass the one it already has.
  declaredNamesFrom =
    pinnedNames: cfg:
    pinnedNames
    ++ lib.attrNames cfg.networking.bridges
    ++ lib.attrNames cfg.networking.bonds
    ++ lib.attrNames cfg.networking.vlans
    ++ lib.attrNames cfg.networking.macvlans
    ++ lib.attrNames cfg.networking.ipvlans
    ++ lib.attrNames cfg.networking.vswitches
    ++ lib.attrNames cfg.networking.wlanInterfaces
    ++ lib.attrNames cfg.networking.sits
    ++ lib.attrNames cfg.networking.greTunnels
    ++ lib.attrNames cfg.networking.wireguard.interfaces
    ++ lib.attrNames cfg.networking.wg-quick.interfaces
    # A netdev is created by systemd-networkd, so it exists only when networkd is
    # enabled; a disabled unit writes nothing either, same reasoning as the
    # disabled .link above. The hosts here run NetworkManager with networkd off,
    # so an ungated netdev name would be backed by nothing.
    # netdevs is keyed by unit basename ("10-vx0"), not by interface name, so a
    # netdev without netdevConfig.Name contributes nothing rather than its key.
    ++ lib.optionals cfg.systemd.network.enable (
      lib.filter (n: n != null) (
        lib.mapAttrsToList (_: netdev: netdev.netdevConfig.Name or null) (
          lib.filterAttrs (_: netdev: netdev.enable or true) cfg.systemd.network.netdevs
        )
      )
    );

  declaredNamesOf = cfg: declaredNamesFrom (classifyLinks cfg.systemd.network.links).pinnedNames cfg;

  body =
    {
      hostName,
      config,
      lib,
      ...
    }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
      # Required, not `or [ ]`: flake.lib.nixos.hosts.<host> is a free-form
      # attrset, so a misspelled key would fall back to no rule and trip none of
      # the guards below. Same reasoning as the required shareCommon entry in
      # modules/configurations/nixos.nix.
      dnsInterfaces =
        hostFlags.firewallDnsInterfaces or (throw (
          "flake.lib.nixos.hosts.${hostName} has no firewallDnsInterfaces entry; "
          + "set it to [ ] explicitly in modules/${hostName}/policy.nix. A missing "
          + "or misspelled key would otherwise emit no firewall rule and trip none "
          + "of the guards in modules/hosts/common/firewall.nix."
        ));
      extraTcpPortRanges = hostFlags.firewallExtraTcpPortRanges or [ ];
      # Required, not `or [ ]`: this free-form registry key generates the
      # source-scoped rules below, so a typo would silently close the intended
      # local service range.
      localTcpPortRanges =
        hostFlags.firewallLocalTcpPortRanges or (throw (
          "flake.lib.nixos.hosts.${hostName} has no firewallLocalTcpPortRanges entry; "
          + "set it to [ ] explicitly in modules/${hostName}/policy.nix. A missing "
          + "or misspelled key would otherwise omit source-scoped TCP rules and "
          + "continue evaluation without the intended local service range."
        ));
      localTcpPortRangeCommands = lib.concatMapStrings (
        range:
        let
          portRange = "${toString range.from}:${toString range.to}";
        in
        lib.concatMapStrings (
          cidr: "iptables -A nixos-fw -s ${cidr} -p tcp --dport ${portRange} -j nixos-fw-accept\n"
        ) localNetworkCidrs
      ) localTcpPortRanges;
      localTcpPortRangeStopCommands = lib.concatMapStrings (
        range:
        let
          portRange = "${toString range.from}:${toString range.to}";
        in
        lib.concatMapStrings (
          cidr: "iptables -D nixos-fw -s ${cidr} -p tcp --dport ${portRange} -j nixos-fw-accept || true\n"
        ) localNetworkCidrs
      ) localTcpPortRanges;
      predictable = config.networking.usePredictableInterfaceNames;
      # One pass over config.systemd.network.links for all six link guards.
      linkClassification = classifyLinks config.systemd.network.links;
      declaredNames = declaredNamesFrom linkClassification.pinnedNames config;
      inherit (linkClassification)
        collidingPins
        duplicatePins
        policyOverriddenPins
        shadowedLinks
        unboundLinks
        defaultShadowedLinks
        ;
      inherit (classify { inherit dnsInterfaces declaredNames predictable; })
        unbackedNames
        staleScheme
        kernelNames
        ;
      staleMessage =
        if predictable then
          "${hostName}: firewallDnsInterfaces has kernel interface names "
          + "(${lib.concatStringsSep ", " staleScheme}) but the host sets "
          + "networking.usePredictableInterfaceNames = true, so they match no device. "
          + "Use the predictable name, or pin the device with a .link Name= outside the "
          + "kernel-assigned namespaces (eth*, wlan*, usb*, wwan*, ib*, sl*) as "
          + "modules/tpnix/networking.nix does."
        else
          "${hostName}: firewallDnsInterfaces has predictable interface names "
          + "(${lib.concatStringsSep ", " staleScheme}) but the host boots with "
          + "net.ifnames=0, so they match no device. Pin the intended device with a .link "
          + "Name= outside the kernel-assigned namespaces (eth*, wlan*, usb*, wwan*, ib*, "
          + "sl*) and name the pin here. If a .link already matches that device, add Name= "
          + "to that file and drop its NamePolicy= rather than authoring a second one, which "
          + "udev never reads. "
          + "A bare kernel name resolves, but to whichever same-class NIC enumerated first "
          + "that boot, which is what the warning below reports.";
      # One row per systemd.network.links guard, in assertion order. A new rule
      # is one row here plus its fixture block in firewall-checks.nix, rather
      # than a third hand-copied assertion stanza to keep in step with the
      # other six.
      linkAssertionTable = [
        {
          result = collidingPins;
          message =
            names:
            "${hostName}: systemd.network.links pins interface names "
            + "(${lib.concatStringsSep ", " names}) inside the namespaces the "
            + "kernel assigns itself (eth*, wlan*, usb*, wwan*, ib*, sl*). Per systemd.link(5) "
            + "the udev rename races the kernel's own assignment there, so the pin may "
            + "silently not apply and anything keyed to the name matches no device. Rename "
            + "the existing pin to a name outside those namespaces, as "
            + "modules/tpnix/networking.nix does with wifi0; do not add a second file, which "
            + "udev never reads.";
        }
        {
          result = duplicatePins;
          message =
            names:
            "${hostName}: enabled systemd.network.links units assign the same pinned "
            + "name (${lib.concatStringsSep ", " names}) to multiple device-specific "
            + "files. One rename wins, while the duplicate name would still count as declared "
            + "here even when one pin does not produce the intended interface name. Pin one "
            + "device per name.";
        }
        {
          result = policyOverriddenPins;
          message =
            names:
            "${hostName}: systemd.network.links units "
            + "(${lib.concatStringsSep ", " names}) set both Name= and "
            + "NamePolicy=. systemd.link(5) gives Name= the lower precedence of the two, so "
            + "the policy wins and the pin silently does not apply wherever NamePolicy is "
            + "honoured. Drop NamePolicy= from a file that pins a name; keep it only in the "
            + "no-Name= altname-narrowing shape (docs/networking/README.md).";
        }
        {
          result = shadowedLinks;
          message =
            names:
            "${hostName}: more than one enabled systemd.network.links unit binds "
            + "(${lib.concatStringsSep ", " names}). udev applies only the first "
            + "matching file, so the rest are never read, while pinnedNamesOf still counts "
            + "their Name= as a declared name. The shadowed file can therefore mask a name "
            + "that matches no device. Add Name= to the file that already matches the device "
            + "instead of authoring a second one (docs/networking/README.md).";
        }
        {
          result = unboundLinks;
          message =
            names:
            "${hostName}: enabled systemd.network.links units (${lib.concatStringsSep ", " names}) "
            + "have no singleton Path= or PermanentMACAddress= selector and either pin a Name= or "
            + "precede another .link. Without a device selector a file applies to every device no "
            + "earlier file matched, so a Name= there renames all of them, and a broad file read "
            + "before a specific one shadows it. Give it a singleton device selector, or drop its "
            + "Name= and place it after the specific files.";
        }
        {
          result = defaultShadowedLinks;
          message =
            names:
            "${hostName}: enabled systemd.network.links units (${lib.concatStringsSep ", " names}) "
            + "sort after systemd's own 99-default.link. udev merges /etc/systemd/network with "
            + "/usr/lib/systemd/network by basename, applies the first file whose [Match] fits, and "
            + "99-default.link matches every device (OriginalName=*), so these files are never read, "
            + "while a Name= in them still counts as declared here. Renumber them below 99-default, "
            + "as the 10-* files in modules/*/networking.nix are.";
        }
      ];
    in
    {
      # A name that matches no device is not an evaluation error on its own:
      # genAttrs below still emits an interfaces entry, so the opening silently
      # does nothing. A name from the wrong naming scheme is provably dead, so
      # that is a hard assertion; an unrecognized name only might be,
      # because a daemon can create an interface no option lists, so that one
      # warns instead.
      assertions = [
        {
          assertion = staleScheme == [ ];
          message = staleMessage;
        }
      ]
      ++ map (row: {
        assertion = row.result == [ ];
        message = row.message row.result;
      }) linkAssertionTable;

      warnings =
        lib.optional (unbackedNames != [ ]) (
          "${hostName}: firewallDnsInterfaces names "
          + "(${lib.concatStringsSep ", " unbackedNames}) are neither predictable nor "
          + "kernel-assigned, and no declaration on this host creates them: no .link Name=, "
          + "bridge, bond, VLAN, macvlan, ipvlan, vswitch, wlan interface, sit, GRE tunnel, "
          + "WireGuard interface, wg-quick interface, or networkd netdev. That is expected "
          + "for an interface a service creates at runtime (tailscale0, docker0); "
          + "otherwise the opening matches no device, so pin it as "
          + "modules/tpnix/networking.nix does."
        )
        # The gap the two guards above leave. staleScheme is empty for a kernel
        # name on a net.ifnames=0 host, and unbackedNames filters kernelRe out, so
        # an unpinned eth0 reached neither. The name resolves, which is why it is
        # a warning: it just resolves to whichever same-class NIC the kernel
        # enumerated first that boot, so the opening moves between devices.
        ++ lib.optional (!predictable && kernelNames != [ ]) (
          "${hostName}: firewallDnsInterfaces names "
          + "(${lib.concatStringsSep ", " kernelNames}) are kernel-assigned and no .link on "
          + "this host pins them, so each follows discovery order and can land on a different "
          + "device across boots. Pin the intended device outside the kernel namespaces. If a "
          + ".link already matches that device, add Name= to that file and drop its "
          + "NamePolicy=; udev applies only the first matching file, so a second .link for the "
          + "same device is never read (docs/networking/README.md)."
        );

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          9999 # Stash default port
        ];
        allowedTCPPortRanges = extraTcpPortRanges;
        # mkMerge, not //: a shallow update would let a dnsInterfaces entry named
        # tailscale0 replace the submodule below and drop the port 22 rule that
        # carries SSH over the tailnet.
        interfaces = lib.mkMerge [
          { tailscale0.allowedTCPPorts = [ 22 ]; }
          (lib.genAttrs dnsInterfaces (_: {
            allowedUDPPorts = [
              53
              67
            ];
            allowedTCPPorts = [ 53 ];
          }))
        ];
        # Allow SSH from local network (10.0.0.0/8)
        extraCommands = ''
          iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept
          ${localTcpPortRangeCommands}
        '';
        extraStopCommands = ''
          iptables -D nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept || true
          ${localTcpPortRangeStopCommands}
        '';
      };
    };
in
{
  flake = {
    lib.nixos = {
      _firewallDnsClassify = classify;
      _firewallDnsPinnedNamesOf = pinnedNamesOf;
      _firewallDnsDeclaredNamesOf = declaredNamesOf;
      _firewallDnsCollidingPinsOf = collidingPinsOf;
      _firewallDnsDuplicatePinsOf = duplicatePinsOf;
      _firewallDnsPolicyOverriddenPinsOf = policyOverriddenPinsOf;
      _firewallDnsShadowedLinksOf = shadowedLinksOf;
      _firewallDnsUnboundLinksOf = unboundLinksOf;
      _firewallDnsDefaultShadowedLinksOf = defaultShadowedLinksOf;
      # Exported so a per-host policy check (e.g.
      # modules/songbird/firewall-policy-check.nix) can compare against the
      # exact CIDR list instead of a hand-copied literal that silently goes
      # stale when this one changes.
      _firewallLocalNetworkCidrs = localNetworkCidrs;
      _firewallStableNamePolicyLinkConfig = stableNamePolicyLinkConfig;
    };
    nixosModules.hosts-common.imports = [ body ];
  };
}
