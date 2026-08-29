# FR-5: no-op override collision check for per-host apps-enable overrides.
#
# The common app catalog (modules/hosts/common/apps-enable.nix) sets app
# defaults under `programs.*.extended.enable` and `services.*.extended.enable`
# at low priority (lib.mkOverride 1100).
# Per-host override files such as modules/tpnix/apps-enable.nix layer a higher
# priority value (lib.mkOverride 1000) for entries that diverge from the
# common baseline.
#
# An entry in a per-host override that sets the SAME value as the common
# baseline is a no-op: it adds noise without changing behavior. This check
# throws at evaluation time when such duplicates are found, so the CI gate
# that forces check drvPaths with `nix eval` fails (not only a full
# `nix flake check` that builds checks), prompting the author to delete the
# redundant entry.
#
# Hosts opt in by publishing their override attrset under
# `flake.lib.nixos._hostAppsOverrides.<host>`. A `host-<host>-apps-no-noop`
# check is emitted automatically for each opted-in host.
#
# That attrset is flat, one boolean per app, and routes to a fixed
# `extended.enable`, so it cannot carry an override of a nested toggle such as
# `claude-code.extended.installMethods.bun.enable`. Those are registered
# separately under `flake.lib.nixos._hostAppsSubToggleOverrides.<host>` as a
# list of `{ path; value; }` under `programs`, and the host file builds the
# override from that list rather than writing it out, so an unregistered one
# cannot exist. Without this the same no-op drift is invisible: the comparison
# below reads a fixed `extended.enable` and only iterates names the flat set
# registered.
#
# The comparison is done at flake.lib level (no module evaluation) to avoid
# the infinite recursion that arises when reading
# `config.configurations.nixos.<host>.module` back from a flake-level check.
{ config, lib, ... }:
let
  baseline = config.flake.lib.nixos._commonAppsBaseline or { };
  baselinePrograms = baseline.programs or { };
  baselineServices = baseline.services or { };
  hostOverrides = config.flake.lib.nixos._hostAppsOverrides or { };
  hostSubToggles = config.flake.lib.nixos._hostAppsSubToggleOverrides or { };
  baselineKeys = baselinePrograms // baselineServices;
  unknownOverridesByHost = lib.mapAttrs (
    _host: overrides:
    builtins.filter (name: !(lib.hasAttr name baselineKeys)) (builtins.attrNames overrides)
  ) hostOverrides;
  unknownOverridesByHostNonEmpty = lib.filterAttrs (
    _host: names: names != [ ]
  ) unknownOverridesByHost;
  anyUnknownOverrides = unknownOverridesByHostNonEmpty != { };
  unknownOverridesSummary = lib.concatStringsSep "; " (
    lib.mapAttrsToList (
      host: names: "${host}: ${lib.concatStringsSep ", " names}"
    ) unknownOverridesByHostNonEmpty
  );
  baselineMissing =
    (hostOverrides != { } || hostSubToggles != { })
    && (
      (baselinePrograms == { } && baselineServices == { })
      || anyUnknownOverrides
      || anyUncomparableSubToggles
    );
  baselineMissingMessage =
    if anyUnknownOverrides then
      "FR-5 baseline snapshot missing or out of sync: "
      + "flake.lib.nixos._commonAppsBaseline does not declare every entry in "
      + "flake.lib.nixos._hostAppsOverrides.<host>: "
      + unknownOverridesSummary
    else if anyUncomparableSubToggles then
      "FR-5 baseline snapshot out of sync: "
      + "flake.lib.nixos._commonAppsBaseline declares no value at these "
      + "flake.lib.nixos._hostAppsSubToggleOverrides.<host> paths, so they are "
      + "registered but never compared: "
      + uncomparableSubTogglesSummary
    else
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
      programEntry = baselinePrograms.${app} or null;
      serviceEntry = baselineServices.${app} or null;
      entry = if programEntry != null then programEntry else serviceEntry;
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

  # A path the baseline never declares cannot be compared at all, so it is
  # reported rather than dropped: dropping it makes registration look like
  # coverage it does not provide, which is the asymmetry against the flat set,
  # where an unknown name is an eval-time failure through unknownOverridesByHost.
  subToggleUncomparableFor =
    toggles:
    map (toggle: lib.concatStringsSep "." toggle.path) (
      builtins.filter (toggle: (lib.attrByPath toggle.path null baselinePrograms) == null) toggles
    );

  uncomparableSubTogglesByHost = lib.filterAttrs (_host: paths: paths != [ ]) (
    lib.mapAttrs (_host: subToggleUncomparableFor) hostSubToggles
  );
  anyUncomparableSubToggles = uncomparableSubTogglesByHost != { };
  uncomparableSubTogglesSummary = lib.concatStringsSep "; " (
    lib.mapAttrsToList (
      host: paths: "${host}: ${lib.concatStringsSep ", " paths}"
    ) uncomparableSubTogglesByHost
  );

  subToggleNoOpsFor =
    toggles:
    let
      isNoOp =
        toggle:
        let
          base = unwrapOverride (lib.attrByPath toggle.path null baselinePrograms);
        in
        base != null && base == toggle.value;
    in
    map (toggle: lib.concatStringsSep "." toggle.path) (builtins.filter isNoOp toggles);

  # Keyed on the union of both registries. A host whose only divergence is
  # nested registers no flat set, and keying on hostOverrides alone emits no
  # host-<host>-apps-no-noop check for it at all, rather than a passing one.
  noOpsByHost = lib.mapAttrs (
    host: _:
    noOpsFor (hostOverrides.${host} or { }) ++ subToggleNoOpsFor (hostSubToggles.${host} or [ ])
  ) (hostOverrides // hostSubToggles);

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
          # throw, not a failing derivation: CI forces each check's drvPath
          # with `nix eval` and never builds checks, so only an eval-time
          # failure gates CI (same rationale as modules/meta/ci-lix-parity.nix).
          if baselineMissing then
            throw baselineMissingMessage
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
            throw (messageFor host noOps)
        )
      ) noOpsByHost;
    };
}
