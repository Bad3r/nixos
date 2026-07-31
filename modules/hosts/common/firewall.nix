# Shared firewall skeleton. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.firewallDnsInterfaces
#     Interfaces allowed to serve DNS/DHCP (UDP 53/67, TCP 53).
#   flake.lib.nixos.hosts.<host>.firewallExtraTcpPortRanges
#     Additional globally open TCP port ranges.
{ config, lib, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  # Bound once each: the three classifier outputs stay mutually consistent only
  # while both patterns are single-sourced.
  # enp4s0, eno1, ens3, enx001122334455, wlp0s20f3, wwp0s20f0u2, ibp5s0.
  predictableRe = "(en|wl|ww|ib)[posx].*";
  # Kernel-assigned. usb0 is the usbnet default: drivers/net/usb/usbnet.c only
  # switches to eth%d, wlan%d, or wwan%d for drivers flagged FLAG_ETHER,
  # FLAG_WLAN, or FLAG_WWAN, so a cdc_ether tether comes up as usb0.
  kernelRe = "(eth|wlan|usb|wwan|ib)[0-9]+";
  matches = re: n: lib.match re n != null;

  # Pure classifier, exported so modules/hosts/common/firewall-checks.nix can
  # exercise every branch: both hosts leave firewallDnsInterfaces empty, so
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

  # Names a .link Name= creates on a host, such as lan0. A disabled unit is
  # never installed, and a .link with an empty [Match] matches every device udev
  # initializes: it renames whichever interface appears first and shadows every
  # higher-numbered .link file, so it does not bind a name to a device. Neither
  # counts as a pin.
  pinnedNamesOf =
    links:
    lib.filter (n: n != null) (
      lib.mapAttrsToList (
        _: link:
        if !(link.enable or true) || link.matchConfig or { } == { } then
          null
        else
          link.linkConfig.Name or null
      ) links
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
    # A disabled netdev writes no unit, so nothing creates the interface; same
    # reasoning as the disabled .link above.
    ++ lib.mapAttrsToList (n: netdev: netdev.netdevConfig.Name or n) (
      lib.filterAttrs (_: netdev: netdev.enable or true) cfg.systemd.network.netdevs
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
      predictable = config.networking.usePredictableInterfaceNames;
      declaredNames = declaredNamesOf config;
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
          + "kernel-assigned namespaces (eth*, wlan*, usb*, wwan*, ib*) as "
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
        '';
        extraStopCommands = ''
          iptables -D nixos-fw -s 10.0.0.0/8 -p tcp --dport 22 -j nixos-fw-accept || true
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
    };
    nixosModules.hosts-common.imports = [ body ];
  };
}
