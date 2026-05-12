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
# Hosts opt in by publishing their override attrset under
# `flake.lib.nixos._hostAppsOverrides.<host>`. A `host-<host>-apps-no-noop`
# check is emitted automatically for each opted-in host.
#
# The comparison is done at flake.lib level (no module evaluation) to avoid
# the infinite recursion that arises when reading
# `config.configurations.nixos.<host>.module` back from a flake-level check.
{ config, lib, ... }:
let
  baseline = config.flake.lib.nixos._commonAppsBaseline or { };
  hostOverrides = config.flake.lib.nixos._hostAppsOverrides or { };
  baselineMissing = hostOverrides != { } && baseline == { };
  baselineMissingMessage =
    "FR-5 baseline snapshot missing: flake.lib.nixos._commonAppsBaseline is empty "
    + "but host overrides are registered.";

  # Baseline values come from `lib.mkOverride 1100 <bool>`, which wraps the
  # boolean in `{ _type = "override"; priority = 1100; content = <bool>; }`.
  # Per-host overrides are raw booleans, so the wrapper must be unpeeled
  # before comparison or `==` is always false.
  unwrapOverride = v: if lib.isAttrs v && (v._type or "") == "override" then v.content else v;

  baselineEnableOf =
    app:
    let
      entry = baseline.${app} or null;
    in
    if entry == null then null else unwrapOverride (entry.extended.enable or null);

  noOpsFor =
    overrides:
    let
      isNoOp =
        app:
        let
          base = baselineEnableOf app;
          over = overrides.${app};
        in
        base != null && base == over;
    in
    builtins.filter isNoOp (builtins.attrNames overrides);

  noOpsByHost = lib.mapAttrs (_host: noOpsFor) hostOverrides;

  messageFor =
    host: noOps:
    "FR-5: ${host} apps-enable override duplicates common baseline (no-op). "
    + "Remove these entries from modules/${host}/apps-enable.nix: "
    + lib.concatStringsSep ", " noOps;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        host-apps-baseline-present =
          if baselineMissing then
            pkgs.runCommandLocal "host-apps-baseline-missing-fail"
              {
                message = baselineMissingMessage;
              }
              ''
                printf '%s\n' "$message" >&2
                exit 1
              ''
          else
            pkgs.runCommandLocal "host-apps-baseline-present-ok" { } ''
              echo "ok: common app baseline snapshot is present when host overrides are registered" > $out
            '';
      }
      // lib.mapAttrs' (
        host: noOps:
        lib.nameValuePair "host-${host}-apps-no-noop" (
          if noOps == [ ] then
            pkgs.runCommandLocal "host-${host}-apps-no-noop-ok" { } ''
              echo "ok: ${host} apps override file contains no no-op entries" > $out
            ''
          else
            pkgs.runCommandLocal "host-${host}-apps-no-noop-fail"
              {
                message = messageFor host noOps;
              }
              ''
                printf '%s\n' "$message" >&2
                exit 1
              ''
        )
      ) noOpsByHost;
    };
}
