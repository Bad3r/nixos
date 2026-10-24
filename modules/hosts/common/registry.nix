# Every host under configurations.nixos needs an explicit shareCommon entry
# here; modules/configurations/nixos.nix aborts evaluation for hosts without
# one, so a new host cannot silently skip the hosts-common baseline.
# shareCommon = false is a deliberate opt-out, not the default.
{ config, ... }:
{
  # Returns a Boolean: lib.nixos is `anything`, which deep-merges the result of
  # a function and would walk into whole nixosConfigurations.
  flake.lib.nixos._isShareCommonHost =
    name: config.flake.lib.nixos.hosts.${name}.shareCommon or false;

  flake.lib.nixos.hosts = {
    songbird.shareCommon = true; # hostname: songbird.internal
    # libvirt guest on songbird (modules/workloads/guests/nixos-dev/).
    nixos-dev.shareCommon = false;
  };
}
