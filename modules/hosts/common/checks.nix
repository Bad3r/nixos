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
# redundant entry. A path registered twice within one host is rejected the
# same way, since the host builder below throws on it.
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
#
# The portal parity checks below run at build time because CI evaluates every
# check's drvPath without building it before selecting runtime checks.
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

  # lib.recursiveUpdate in hostAppsFor would fold a path registered twice
  # (overrides plus a colliding subToggles entry) silently, later entry wins.
  duplicateNamesOf =
    toggles:
    lib.attrNames (
      lib.filterAttrs (_: count: count > 1) (
        lib.foldl' (acc: toggle: acc // { ${nameOf toggle} = (acc.${nameOf toggle} or 0) + 1; }) { } toggles
      )
    );
  duplicateMessage =
    host: names:
    "modules/${host}/apps-enable.nix registers "
    + lib.concatStringsSep ", " names
    + " more than once; the later registration silently wins, so remove the duplicate.";

  # lib.recursiveUpdate in `landing` also corrupts an override node when one
  # registered path is a strict prefix of another's: the shorter path's
  # mkOverride wrapper gains the longer path's tail as a sibling attribute,
  # and the module system then reads only that wrapper's `.content`, so the
  # sibling silently never lands instead of erroring like duplicateNamesOf
  # catches for an exact repeat.
  prefixCollisionsOf =
    toggles:
    lib.concatMap (
      a:
      lib.concatMap (
        b:
        lib.optional (
          lib.length a.path < lib.length b.path && lib.take (lib.length a.path) b.path == a.path
        ) "${nameOf a} is a prefix of ${nameOf b}"
      ) toggles
    ) toggles;
  collisionMessage =
    host: collisions:
    "modules/${host}/apps-enable.nix registers "
    + lib.concatStringsSep "; " collisions
    + "; a shorter registered path corrupts a longer sibling's mkOverride wrapper when both land "
    + "through lib.recursiveUpdate, so split or remove one.";

  # One baseline lookup per toggle; every classification below reads the
  # resolved entry rather than looking the path up again.
  resolveToggles =
    lookup:
    map (toggle: {
      inherit toggle;
      hit = lookup toggle.path;
    });

  # Read side, exported so modules/hosts/common/apps-sub-toggle-checks.nix can
  # exercise every branch against a snapshot of its own rather than the live
  # baseline.
  classifyRegistry =
    snapshot: registry:
    let
      toggles = togglesOf registry;
      resolved = resolveToggles (lookupIn (snapshotOf snapshot)) toggles;
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
      # Reported here as well as thrown by hostAppsFor, so the perSystem check
      # rejects the same registry the host evaluation rejects.
      duplicates = duplicateNamesOf toggles ++ prefixCollisionsOf toggles;
    };

  # Write side: the same lookup decides where each entry lands. A path absent
  # from both namespaces throws here, inside the host evaluation, because the
  # FR-5 check that also reports it is a perSystem check nixos-rebuild never
  # evaluates; writing nothing would drop the override from the switched
  # closure without a diagnostic.
  hostAppsFor =
    host: snapshot: registry:
    let
      toggles = togglesOf registry;
      duplicateNames = duplicateNamesOf toggles;
      prefixCollisions = prefixCollisionsOf toggles;
      namespaceOf =
        entry:
        if entry.hit != null then
          entry.hit.namespace
        else
          throw (
            "modules/${host}/apps-enable.nix registers ${nameOf entry.toggle}, which "
            + "flake.lib.nixos._commonAppsBaseline declares under neither programs nor services, "
            + "so the override has nowhere to land; declare it in modules/hosts/common/apps-enable.nix "
            + "or drop the registration."
          );
      # Both namespace passes filter this one list, so each toggle is resolved
      # once rather than once per pass.
      resolved = map (entry: entry // { namespace = namespaceOf entry; }) (
        resolveToggles (lookupIn (snapshotOf snapshot)) toggles
      );
      landing =
        namespace:
        lib.foldl' (
          acc: entry:
          lib.recursiveUpdate acc (
            lib.setAttrByPath entry.toggle.path (lib.mkOverride 1000 entry.toggle.value)
          )
        ) { } (builtins.filter (entry: entry.namespace == namespace) resolved);
    in
    if duplicateNames != [ ] then
      throw (duplicateMessage host duplicateNames)
    else if prefixCollisions != [ ] then
      throw (collisionMessage host prefixCollisions)
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
    + "Remove these entries from modules/${host}/apps-enable.nix (flat appEnable "
    + "entries are shown with their extended.enable suffix): "
    + lib.concatStringsSep ", " noOps;

  portalPreferences = config.flake.lib.nixos._portalPreferences or null;
  # Include explicit `none` entries in policy coverage; `default` is a profile
  # fallback and is not an interface policy.
  portalInterfaceKeys =
    if portalPreferences == null then
      [ ]
    else
      builtins.filter (name: lib.hasPrefix "org.freedesktop.impl.portal." name) (
        builtins.attrNames portalPreferences
      );
  portalInterfacesFor =
    backend:
    if portalPreferences == null then
      [ ]
    else
      builtins.filter (
        name: builtins.elem backend (lib.toList portalPreferences.${name})
      ) portalInterfaceKeys;
  gtkPortalInterfaces = portalInterfacesFor "gtk";
  gnomeKeyringPortalInterfaces = portalInterfacesFor "gnome-keyring";
in
{
  flake.lib.hostApps = {
    classify = classifyRegistry;
    forRegistry = hostAppsFor;
    mk = mkHostApps;
  };

  perSystem =
    { pkgs, ... }:
    let
      portalInterfaceParity =
        {
          checkName,
          portalPackage,
          portalBasename,
          expectedInterfaces,
          requireExpectedSubset,
          requireActualSubset,
        }:
        if !(requireExpectedSubset || requireActualSubset) then
          throw "${checkName}: no portal comparison direction is configured"
        else
          pkgs.runCommandLocal checkName
            {
              # The CI check-compliance job evaluates drvPath first and
              # builds derivations marked with runtimeCheck afterward.
              passthru.runtimeCheck = true;
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.gawk
              ];
            }
            ''
              set -euo pipefail

              portal_file=${lib.escapeShellArg "${portalPackage}/share/xdg-desktop-portal/portals/${portalBasename}.portal"}
              expected_file="$TMPDIR/expected"
              actual_unsorted="$TMPDIR/actual-unsorted"
              actual_file="$TMPDIR/actual"

              if [ ! -f "$portal_file" ]; then
                echo "${checkName}: missing $portal_file" >&2
                exit 1
              fi

              interface_line_count=$(awk '$0 ~ /^Interfaces=/ { count += 1 } END { print count + 0 }' "$portal_file")
              if [ "$interface_line_count" -ne 1 ]; then
                echo "${checkName}: expected one Interfaces= line in $portal_file, found $interface_line_count" >&2
                exit 1
              fi

              interfaces_value=$(awk '$0 ~ /^Interfaces=/ { print substr($0, 12) }' "$portal_file")
              if [ -z "$interfaces_value" ]; then
                echo "${checkName}: Interfaces= is empty in $portal_file" >&2
                exit 1
              fi

              # Portal metadata uses a semicolon-delimited list; permit one
              # trailing delimiter while rejecting repeated or interior delimiters.
              case "$interfaces_value" in
                *';') interfaces_value=''${interfaces_value%;} ;;
              esac
              if [ -z "$interfaces_value" ]; then
                echo "${checkName}: Interfaces= has no interface values in $portal_file" >&2
                exit 1
              fi

              empty_interface_count=$(awk -F ';' '{ for (i = 1; i <= NF; i++) if ($i == "") count += 1 } END { print count + 0 }' <<<"$interfaces_value")
              if [ "$empty_interface_count" -ne 0 ]; then
                echo "${checkName}: Interfaces= contains an empty entry in $portal_file" >&2
                exit 1
              fi

              awk -F ';' '{ for (i = 1; i <= NF; i++) print $i }' <<<"$interfaces_value" > "$actual_unsorted"
              duplicate_interfaces=$(sort "$actual_unsorted" | uniq -d)
              if [ -n "$duplicate_interfaces" ]; then
                echo "${checkName}: Interfaces= contains duplicate entries:" >&2
                printf '%s\n' "$duplicate_interfaces" >&2
                exit 1
              fi

              expected_interfaces=(${lib.escapeShellArgs expectedInterfaces})
              if [ "''${#expected_interfaces[@]}" -eq 0 ]; then
                : > "$expected_file"
              else
                printf '%s\n' "''${expected_interfaces[@]}" | sort -u > "$expected_file"
              fi
              sort -u "$actual_unsorted" > "$actual_file"

              if ${lib.boolToString requireExpectedSubset}; then
                missing_interfaces=$(comm -23 "$expected_file" "$actual_file")
                if [ -n "$missing_interfaces" ]; then
                  echo "${checkName}: packaged ${portalBasename}.portal is missing expected interfaces:" >&2
                  printf '%s\n' "$missing_interfaces" >&2
                  exit 1
                fi
              fi

              if ${lib.boolToString requireActualSubset}; then
                unexpected_interfaces=$(comm -13 "$expected_file" "$actual_file")
                if [ -n "$unexpected_interfaces" ]; then
                  echo "${checkName}: packaged ${portalBasename}.portal advertises interfaces without explicit policy:" >&2
                  printf '%s\n' "$unexpected_interfaces" >&2
                  exit 1
                fi
              fi

              printf 'ok: %s.portal Interfaces= satisfies comparison against %s expected interfaces\n' "${portalBasename}" "${toString (builtins.length expectedInterfaces)}" > "$out"
            '';
    in
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

        portal-gtk-interface-parity =
          # Keep route coverage separate from policy coverage so explicit
          # `none` mappings do not look like missing GTK package interfaces.
          if portalPreferences == null then
            throw (
              "portal-gtk-interface-parity: modules/hosts/common/gsettings.nix no longer exports "
              + "flake.lib.nixos._portalPreferences, so the GTK interface pins are unverified."
            )
          else if gtkPortalInterfaces == [ ] then
            throw "portal-gtk-interface-parity: no portal interfaces are pinned to gtk"
          else
            portalInterfaceParity {
              checkName = "portal-gtk-interface-parity";
              portalPackage = pkgs.xdg-desktop-portal-gtk;
              portalBasename = "gtk";
              expectedInterfaces = gtkPortalInterfaces;
              requireExpectedSubset = true;
              requireActualSubset = false;
            };

        portal-gtk-policy-parity =
          if portalPreferences == null then
            throw (
              "portal-gtk-policy-parity: modules/hosts/common/gsettings.nix no longer exports "
              + "flake.lib.nixos._portalPreferences, so the packaged GTK interface policy is unverified."
            )
          else
            portalInterfaceParity {
              checkName = "portal-gtk-policy-parity";
              portalPackage = pkgs.xdg-desktop-portal-gtk;
              portalBasename = "gtk";
              expectedInterfaces = portalInterfaceKeys;
              requireExpectedSubset = false;
              requireActualSubset = true;
            };

        portal-gnome-keyring-interface-parity =
          if portalPreferences == null then
            throw (
              "portal-gnome-keyring-interface-parity: modules/hosts/common/gsettings.nix no longer exports "
              + "flake.lib.nixos._portalPreferences, so the Secret interface pin is unverified."
            )
          else if gnomeKeyringPortalInterfaces == [ ] then
            # No interface is routed to gnome-keyring, so its portal artifact is not selected.
            pkgs.runCommandLocal "portal-gnome-keyring-interface-parity-skipped" { } ''
              echo "ok: no portal interface is routed to gnome-keyring" > $out
            ''
          else
            portalInterfaceParity {
              checkName = "portal-gnome-keyring-interface-parity";
              portalPackage = pkgs.gnome-keyring;
              portalBasename = "gnome-keyring";
              expectedInterfaces = gnomeKeyringPortalInterfaces;
              requireExpectedSubset = true;
              requireActualSubset = false;
            };
      }
      // lib.mapAttrs' (
        host: result:
        lib.nameValuePair "host-${host}-apps-no-noop" (
          if result.duplicates != [ ] then
            throw (duplicateMessage host result.duplicates)
          else if result.noOps != [ ] then
            throw (messageFor host result.noOps)
          else
            pkgs.runCommandLocal "host-${host}-apps-no-noop-ok" { } ''
              echo "ok: ${host} apps override file contains no no-op or duplicate entries" > $out
            ''
        )
      ) classificationByHost;
    };
}
