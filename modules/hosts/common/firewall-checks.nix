# Coverage for the firewallDnsInterfaces classifier in
# modules/hosts/common/firewall.nix.
#
# Every host currently sets `firewallDnsInterfaces = [ ]`, so both assertions
# and the warning in that module are vacuously true in every host closure
# `nix flake check` evaluates. Without this file a typo in one regex
# alternative, or a nixpkgs option renamed out of `declaredNames`, passes the
# whole suite. The cases below are the ones verified by hand while the
# classifier was written.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/checks.nix).
{ config, lib, ... }:
let
  classify = config.flake.lib.nixos._firewallDnsClassify or null;
  pinnedNamesOf = config.flake.lib.nixos._firewallDnsPinnedNamesOf or null;

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
      name = "link with an empty match is not a pin";
      links."10-lan0" = link { } "lan0";
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
      name = "wwan and infiniband predictable prefixes";
      dnsInterfaces = [
        "wwp0s20f0u2"
        "ibp5s0"
      ];
      declaredNames = [ ];
      predictableNames = [
        "wwp0s20f0u2"
        "ibp5s0"
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
      ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [
        "usb0"
        "wwan0"
        "ib0"
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
      name = "empty input stays empty";
      dnsInterfaces = [ ];
      declaredNames = [ ];
      predictableNames = [ ];
      kernelNames = [ ];
      unbackedNames = [ ];
    }
  ];

  fmt = names: "[ ${lib.concatStringsSep " " names} ]";

  classifyFailures = lib.concatMap (
    case:
    let
      got = classify { inherit (case) dnsInterfaces declaredNames; };
      mismatch =
        field:
        lib.optional (
          got.${field} != case.${field}
        ) "${case.name}: ${field} = ${fmt got.${field}}, expected ${fmt case.${field}}";
    in
    mismatch "predictableNames" ++ mismatch "kernelNames" ++ mismatch "unbackedNames"
  ) classifyCases;

  pinnedFailures = lib.concatMap (
    case:
    let
      got = pinnedNamesOf case.links;
    in
    lib.optional (got != case.expected) "${case.name}: got ${fmt got}, expected ${fmt case.expected}"
  ) pinnedCases;

  failures = classifyFailures ++ pinnedFailures;

  missingExports = classify == null || pinnedNamesOf == null;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.firewall-dns-interface-classifier =
        if missingExports then
          throw (
            "firewall-dns-interface-classifier: modules/hosts/common/firewall.nix no longer exports "
            + "flake.lib.nixos._firewallDnsClassify and _firewallDnsPinnedNamesOf, so the "
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
            echo "ok: ${toString (lib.length classifyCases + lib.length pinnedCases)} classifier cases" > $out
          '';
    };
}
