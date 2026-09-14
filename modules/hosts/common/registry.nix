# Every host under configurations.nixos needs an explicit shareCommon entry
# here; modules/configurations/nixos.nix aborts evaluation for hosts without
# one, so a new host cannot silently skip the hosts-common baseline.
# shareCommon = false is a deliberate opt-out, not the default.
{ config, lib, ... }:
let
  hosts = config.flake.lib.nixos.hosts;
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");

  # Cloudflare assigns Mesh device addresses from 100.96.0.0/12: second octet
  # 96 to 111, then two full octets. No leading zeros, so the accepted text is
  # exactly what `ip -4 addr show CloudflareWARP` prints.
  octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
  meshRange = "100\\.(9[6-9]|10[0-9]|11[01])\\.${octet}\\.${octet}";
  meshIpIsValid = value: lib.isString value && builtins.match meshRange value != null;

  # Cloudflare Mesh device address of a registered host, or null while the host
  # is not enrolled. Anything outside the Mesh block must fail here:
  # modules/networking/ssh-hosts.nix interpolates the value into a `HostName`
  # line and modules/hosts/common/ssh-known-hosts.nix into a host-key pin, so a
  # pasted address from another network renders an alias that never connects,
  # and an embedded newline would inject ssh directives on every fleet host.
  meshIpOfIn =
    hosts: name:
    let
      value = hosts.${name}.meshIp or null;
    in
    if value == null then
      null
    else if meshIpIsValid value then
      value
    else
      throw "flake.lib.nixos.hosts.${name}.meshIp must be an IPv4 address inside the Cloudflare Mesh block 100.96.0.0/12 when set";

  meshIpTests = [
    {
      name = "no meshIp";
      hosts.alpha = { };
      expected = null;
    }
    {
      name = "null meshIp";
      hosts.alpha.meshIp = null;
      expected = null;
    }
    {
      name = "first Mesh address";
      hosts.alpha.meshIp = "100.96.0.0";
      expected = "100.96.0.0";
    }
    {
      name = "last Mesh address";
      hosts.alpha.meshIp = "100.111.255.255";
      expected = "100.111.255.255";
    }
    {
      name = "address in the middle of the block";
      hosts.alpha.meshIp = "100.104.7.19";
      expected = "100.104.7.19";
    }
    {
      name = "address below the block";
      hosts.alpha.meshIp = "100.95.255.255";
      expectFailure = true;
    }
    {
      name = "address above the block";
      hosts.alpha.meshIp = "100.112.0.0";
      expectFailure = true;
    }
    {
      name = "tailnet address";
      hosts.alpha.meshIp = "100.120.100.117";
      expectFailure = true;
    }
    {
      name = "octet past 255";
      hosts.alpha.meshIp = "100.96.0.256";
      expectFailure = true;
    }
    {
      name = "leading zero";
      hosts.alpha.meshIp = "100.096.0.9";
      expectFailure = true;
    }
    {
      name = "prefix length appended";
      hosts.alpha.meshIp = "100.96.0.9/32";
      expectFailure = true;
    }
    {
      name = "trailing newline";
      hosts.alpha.meshIp = "100.96.0.9\n";
      expectFailure = true;
    }
    {
      name = "embedded ssh directive";
      hosts.alpha.meshIp = "100.96.0.9\n  ProxyCommand true";
      expectFailure = true;
    }
    {
      name = "empty string";
      hosts.alpha.meshIp = "";
      expectFailure = true;
    }
    {
      name = "whitespace only";
      hosts.alpha.meshIp = "   ";
      expectFailure = true;
    }
    {
      name = "not a string";
      hosts.alpha.meshIp = 100;
      expectFailure = true;
    }
  ];
  meshIpTestFailures = lib.concatMap (
    test:
    let
      result = builtins.tryEval (meshIpOfIn test.hosts "alpha");
    in
    if test.expectFailure or false then
      lib.optional result.success "${test.name}: accepted ${builtins.toJSON result.value}, expected a throw"
    else if !result.success then
      [ "${test.name}: threw, expected ${builtins.toJSON test.expected}" ]
    else
      lib.optional (
        result.value != test.expected
      ) "${test.name}: got ${builtins.toJSON result.value}, expected ${builtins.toJSON test.expected}"
  ) meshIpTests;
in
{
  flake.lib.nixos.hosts = {
    songbird.shareCommon = true;
    tpnix.shareCommon = true;
  };

  flake.lib.nixos.meshIpOf = meshIpOfIn hosts;

  perSystem =
    { pkgs, ... }:
    {
      checks.hosts-common-mesh-ip =
        if meshIpTestFailures != [ ] then
          throw (formatCaseFailures "hosts-common-mesh-ip" meshIpTestFailures)
        else
          pkgs.runCommandLocal "hosts-common-mesh-ip-ok" { } "touch $out";
    };
}
