# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallDnsInterfaces
#     Interfaces allowed to serve DNS/DHCP (UDP 53/67, TCP 53).
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
#   flake.lib.nixos.hosts.<host>.firewallLocalTcpPortRanges
#     Additional TCP port ranges open from RFC1918 local IPv4 networks.
{ config, lib, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  localNetworkCidrs = [
    "10.0.0.0/8"
    "192.168.0.0/16"
  ];

  # Bound once each: the three classifier outputs stay mutually consistent only
  # while both patterns are single-sourced.
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
      # choice: both hosts pass an empty dnsInterfaces, which makes an inverted
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

  # A [Match] that is empty, whose selector is a glob, or which carries more than
  # one value matches each device udev initializes: it renames whichever
  # interface appears first and shadows every higher-numbered .link file, so it
  # does not bind a name. systemd.link(5) selectors are "a whitespace-separated
  # list of shell-style globs", so both the list and the glob forms are checked.
  bindsOneValue =
    value:
    let
      # Split on any whitespace run, not just spaces: systemd.link(5) calls these
      # "whitespace-separated" lists, and a tab or newline in a Nix multi-line
      # string separates values just as well. builtins.split drops empty tokens,
      # which also covers the empty assignment that resets the list.
      tokens = lib.filter (t: lib.isString t && t != "") (
        lib.concatMap (builtins.split "[[:space:]]+") (lib.toList value)
      );
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

  bindsOneDevice =
    matchConfig:
    lib.any (key: matchConfig ? ${key} && bindsOneValue matchConfig.${key}) bindingMatchKeys;

  # Names a .link Name= creates on a host, such as lan0. A disabled unit is
  # never installed and a match-all file does not bind a name to a device, so
  # neither counts as a pin.
  pinnedNamesOf =
    links:
    lib.filter (n: n != null) (
      lib.mapAttrsToList (
        _: link:
        if !(link.enable or true) || !(bindsOneDevice (link.matchConfig or { })) then
          null
        else
          link.linkConfig.Name or null
      ) links
    );

  # Pins into a namespace the kernel assigns itself. systemd.link(5) on Name=:
  # "specifying a name that the kernel might use for another interface (for
  # example eth0) is dangerous because the name assignment done by udev will
  # race with the assignment done by the kernel ... making the naming
  # unpredictable". A pin that loses that race leaves the device on its kernel
  # name, so anything keyed to the pinned name matches nothing.
  # Derived from every enabled link rather than from pinnedNamesOf: a collision
  # is a property of the name a .link writes, not of whether it binds to one
  # device. A match-all file named eth0 is the worse case, not an excluded one.
  collidingPinsOf =
    links:
    lib.filter (matches kernelRe) (
      lib.filter (n: n != null) (
        lib.mapAttrsToList (
          _: link: if link.enable or true then link.linkConfig.Name or null else null
        ) links
      )
    );

  # Interfaces a host declares rather than inherits from a NIC. Exported with
  # the classifier so the check can assert every source is still read.
  declaredNamesOf =
    cfg:
    pinnedNamesOf cfg.systemd.network.links
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
      declaredNames = declaredNamesOf config;
      collidingPins = collidingPinsOf config.systemd.network.links;
      inherit (classify { inherit dnsInterfaces declaredNames predictable; })
        unbackedNames
        staleScheme
        ;
      staleMessage =
        if predictable then
          "${hostName}: firewallDnsInterfaces has kernel interface names "
          + "(${lib.concatStringsSep ", " staleScheme}) but the host sets "
          + "networking.usePredictableInterfaceNames = true, so they match no device. "
          + "Use the predictable name, or pin the device with a .link Name= outside the "
          + "kernel-assigned namespaces (eth*, wlan*, usb*, wwan*, ib*, sl*) as "
          + "modules/system76/networking.nix does."
        else
          "${hostName}: firewallDnsInterfaces has predictable interface names "
          + "(${lib.concatStringsSep ", " staleScheme}) but the host boots with "
          + "net.ifnames=0, so they match no device. Use the kernel name (eth0, wlan0) "
          + "read from `ip -br link` after the first boot on this configuration.";
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
        {
          assertion = collidingPins == [ ];
          message =
            "${hostName}: systemd.network.links pins interface names "
            + "(${lib.concatStringsSep ", " collidingPins}) inside the namespaces the "
            + "kernel assigns itself (eth*, wlan*, usb*, wwan*, ib*, sl*). Per systemd.link(5) "
            + "the udev rename races the kernel's own assignment there, so the pin may "
            + "silently not apply and anything keyed to the name matches no device. Pin "
            + "outside those namespaces, as modules/system76/networking.nix does with lan0.";
        }
      ];

      warnings = lib.optional (unbackedNames != [ ]) (
        "${hostName}: firewallDnsInterfaces names "
        + "(${lib.concatStringsSep ", " unbackedNames}) are neither predictable nor "
        + "kernel-assigned, and no declaration on this host creates them: no .link Name=, "
        + "bridge, bond, VLAN, macvlan, ipvlan, vswitch, wlan interface, sit, GRE tunnel, "
        + "WireGuard interface, wg-quick interface, or networkd netdev. That is expected "
        + "for an interface a service creates at runtime (tailscale0, docker0); "
        + "otherwise the opening matches no device, so pin it as "
        + "modules/system76/networking.nix does."
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
    };
    nixosModules.hosts-common.imports = [ body ];
  };
}
