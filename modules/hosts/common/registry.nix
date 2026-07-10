# Every host under configurations.nixos needs an explicit shareCommon entry
# here; modules/configurations/nixos.nix aborts evaluation for hosts without
# one, so a new host cannot silently skip the hosts-common baseline.
# shareCommon = false is a deliberate opt-out, not the default.
_: {
  flake.lib.nixos.hosts = {
    system76.shareCommon = true;
    tpnix.shareCommon = true;
  };
}
