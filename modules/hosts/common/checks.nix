# FR-5: no-op override collision check for per-host apps-enable overrides,
# and the builder every host module applies those overrides through.
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
# list of `{ path; value; }`. To this file both registries are one toggle
# list, the flat set being the nested case with a fixed suffix, so a single
# full-path lookup (programs first, services as the fallback) decides what
# this comparison reads and where `flake.lib.hostApps.mk` writes. Host files
# build their module from that builder rather than writing overrides out, so
# an unregistered override cannot exist.
#
# The comparison is done at flake.lib level (no module evaluation) to avoid
# the infinite recursion that arises when reading
# `config.configurations.nixos.<host>.module` back from a flake-level check.
{ config, lib, ... }:
let
  baseline = config.flake.lib.nixos._commonAppsBaseline or { };
  hostOverrides = config.flake.lib.nixos._hostAppsOverrides or { };
  hostSubToggles = config.flake.lib.nixos._hostAppsSubToggleOverrides or { };

  snapshotOf = snapshot: {
    programs = snapshot.programs or { };
    services = snapshot.services or { };
  };
  baselineSnapshot = snapshotOf baseline;

  # The one namespace decision in this file: programs wins, services is the
  # fallback, neither is null. The read side wants the value and the write side
  # wants the label, so both come out of this single lookup and cannot disagree
  # about which namespace owns a path. A shallow `programs // services` merge
  # would resolve a colliding name the other way round.
  lookupIn =
    { programs, services }:
    path:
    let
      fromPrograms = lib.attrByPath path null programs;
      fromServices = lib.attrByPath path null services;
    in
    if fromPrograms != null then
      {
        namespace = "programs";
        value = fromPrograms;
      }
    else if fromServices != null then
      {
        namespace = "services";
        value = fromServices;
      }
    else
      null;

  # Baseline values come from `lib.mkOverride 1100 <bool>`, which wraps the
  # boolean in `{ _type = "override"; priority = 1100; content = <bool>; }`.
  # Per-host overrides are raw booleans, so the wrapper must be unpeeled
  # before comparison or `==` is always false.
  unwrapOverride = v: if lib.isAttrs v && (v._type or "") == "override" then v.content else v;

  # One host's registries as a single toggle list.
  togglesOf =
    {
      overrides ? { },
      subToggles ? [ ],
    }:
    lib.mapAttrsToList (name: value: {
      path = [
        name
        "extended"
        "enable"
      ];
      inherit value;
    }) overrides
    ++ subToggles;
  nameOf = toggle: lib.concatStringsSep "." toggle.path;

  # Read side, exported so modules/hosts/common/apps-sub-toggle-checks.nix can
  # exercise every branch against a snapshot of its own rather than the live
  # baseline.
  classifyRegistry =
    snapshot: registry:
    let
      lookup = lookupIn (snapshotOf snapshot);
      resolved = map (toggle: {
        inherit toggle;
        hit = lookup toggle.path;
      }) (togglesOf registry);
      namesWhere = predicate: map (entry: nameOf entry.toggle) (builtins.filter predicate resolved);
    in
    {
      # A path the baseline never declares cannot be compared at all, so it is
      # reported rather than dropped: dropping it makes registration look like
      # coverage it does not provide.
      uncomparable = namesWhere (entry: entry.hit == null);
      noOps = namesWhere (
        entry: entry.hit != null && unwrapOverride entry.hit.value == entry.toggle.value
      );
    };

  # Write side: the same lookup decides where each entry lands. A path absent
  # from both namespaces throws here, inside the host evaluation, because the
  # FR-5 check that also reports it is a perSystem check nixos-rebuild never
  # evaluates; writing nothing would drop the override from the switched
  # closure without a diagnostic.
  hostAppsFor =
    host: snapshot: registry:
    let
      lookup = lookupIn (snapshotOf snapshot);
      toggles = togglesOf registry;
      # lib.recursiveUpdate below would fold a path registered twice (overrides
      # plus a colliding subToggles entry) silently, later entry wins.
      duplicateNames = lib.attrNames (
        lib.filterAttrs (_: count: count > 1) (
          lib.foldl' (acc: toggle: acc // { ${nameOf toggle} = (acc.${nameOf toggle} or 0) + 1; }) { } toggles
        )
      );
      namespaceOf =
        toggle:
        let
          hit = lookup toggle.path;
        in
        if hit != null then
          hit.namespace
        else
          throw (
            "modules/${host}/apps-enable.nix registers ${nameOf toggle}, which "
            + "flake.lib.nixos._commonAppsBaseline declares under neither programs nor services, "
            + "so the override has nowhere to land; declare it in modules/hosts/common/apps-enable.nix "
            + "or drop the registration."
          );
      landing =
        namespace:
        lib.foldl' (
          acc: toggle:
          lib.recursiveUpdate acc (lib.setAttrByPath toggle.path (lib.mkOverride 1000 toggle.value))
        ) { } (builtins.filter (toggle: namespaceOf toggle == namespace) toggles);
    in
    if duplicateNames != [ ] then
      throw (
        "modules/${host}/apps-enable.nix registers "
        + lib.concatStringsSep ", " duplicateNames
        + " more than once; the later registration silently wins, so remove the duplicate."
      )
    else
      {
        programs = landing "programs";
        services = landing "services";
      };

  # Keyed on the union of both registries. A host whose only divergence is
  # nested registers no flat set, and keying on hostOverrides alone emits no
  # host-<host>-apps-no-noop check for it at all, rather than a passing one.
  registryByHost = lib.mapAttrs (host: _: {
    overrides = hostOverrides.${host} or { };
    subToggles = hostSubToggles.${host} or [ ];
  }) (hostOverrides // hostSubToggles);

  # Built from the registries, not from arguments, so what a host switches is
  # exactly what this file compares; a host name in neither registry is a typo,
  # not an empty override.
  mkHostApps =
    host:
    if registryByHost ? ${host} then
      hostAppsFor host baselineSnapshot registryByHost.${host}
    else
      throw (
        "flake.lib.hostApps.mk: ${host} has no flake.lib.nixos._hostAppsOverrides or "
        + "_hostAppsSubToggleOverrides entry"
      );

  classificationByHost = lib.mapAttrs (_host: classifyRegistry baselineSnapshot) registryByHost;

  uncomparableByHost = lib.filterAttrs (_host: paths: paths != [ ]) (
    lib.mapAttrs (_host: result: result.uncomparable) classificationByHost
  );
  uncomparableSummary = lib.concatStringsSep "; " (
    lib.mapAttrsToList (host: paths: "${host}: ${lib.concatStringsSep ", " paths}") uncomparableByHost
  );
  noOpsByHost = lib.mapAttrs (_host: result: result.noOps) classificationByHost;

  baselineMissing =
    registryByHost != { }
    && (
      (baselineSnapshot.programs == { } && baselineSnapshot.services == { }) || uncomparableByHost != { }
    );
  baselineMissingMessage =
    if uncomparableByHost != { } then
      "FR-5 baseline snapshot out of sync: "
      + "flake.lib.nixos._commonAppsBaseline declares no value at these paths registered under "
      + "flake.lib.nixos._hostAppsOverrides.<host> (shown with their extended.enable suffix) or "
      + "flake.lib.nixos._hostAppsSubToggleOverrides.<host>, so they are registered but never compared: "
      + uncomparableSummary
    else
      "FR-5 baseline snapshot missing: flake.lib.nixos._commonAppsBaseline is empty "
      + "but host overrides are registered.";

  messageFor =
    host: noOps:
    "FR-5: ${host} apps-enable override duplicates common baseline (no-op). "
    + "Remove these entries from modules/${host}/apps-enable.nix: "
    + lib.concatStringsSep ", " noOps;
in
{
  flake.lib.hostApps = {
    classify = classifyRegistry;
    forRegistry = hostAppsFor;
    mk = mkHostApps;
  };

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
