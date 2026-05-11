# FR-5: no-op override collision check for per-host apps-enable overrides.
#
# The common app catalog (modules/hosts/common/apps-enable.nix) sets each
# `programs.<app>.extended.enable` at low priority (lib.mkOverride 1100).
# Per-host override files such as modules/tpnix/apps-enable.nix layer a higher
# priority value (lib.mkOverride 1000) for entries that diverge from the
# common baseline.
#
# An entry in a per-host override that sets the SAME value as the common
# baseline is a no-op: it adds noise without changing behavior. This check
# emits a flake-level assertion that fails `nix flake check` when such
# duplicates are found, prompting the author to delete the redundant entry.
#
# The comparison is done at flake.lib level (no module evaluation) to avoid
# the infinite recursion that arises when reading `config.configurations.nixos.<host>.module`
# back from a flake-level check.
{ config, lib, ... }:
let
  baseline = config.flake.lib.nixos._commonAppsBaseline or { };
  tpnixOverrides = config.flake.lib.nixos._tpnixAppsOverrides or { };

  baselineEnableOf =
    app:
    let
      entry = baseline.${app} or null;
    in
    if entry == null then null else entry.extended.enable or null;

  isNoOp =
    app:
    let
      base = baselineEnableOf app;
      over = tpnixOverrides.${app};
    in
    base != null && base == over;

  noOps = builtins.filter isNoOp (builtins.attrNames tpnixOverrides);

  message =
    "FR-5: tpnix apps-enable override duplicates common baseline (no-op). "
    + "Remove these entries from modules/tpnix/apps-enable.nix: "
    + lib.concatStringsSep ", " noOps;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.host-tpnix-apps-no-noop =
        if noOps == [ ] then
          pkgs.runCommandLocal "host-tpnix-apps-no-noop-ok" { } ''
            echo "ok: tpnix apps override file contains no no-op entries" > $out
          ''
        else
          throw message;
    };
}
