# Every host under configurations.nixos needs an explicit shareCommon entry
# here; modules/configurations/nixos.nix aborts evaluation for hosts without
# one, so a new host cannot silently skip the hosts-common baseline.
# shareCommon = false is a deliberate opt-out, not the default.
{ config, lib, ... }:
let
  hosts = config.flake.lib.nixos.hosts;
in
{
  flake.lib.nixos.hosts = {
    songbird.shareCommon = true;
    tpnix.shareCommon = true;
  };

  # Cloudflare Mesh device address of a registered host, or null while the host is not enrolled.
  # A blank value must fail here: it would render a `HostName` line with no argument and OpenSSH
  # then refuses every connection on the host, not only the Mesh alias.
  flake.lib.nixos.meshIpOf =
    name:
    let
      value = hosts.${name}.meshIp or null;
    in
    if value == null then
      null
    else if lib.types.nonEmptyStr.check value then
      value
    else
      throw "flake.lib.nixos.hosts.${name}.meshIp must be a non-empty string when set";
}
