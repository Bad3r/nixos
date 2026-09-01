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
# The comparison is done at flake.lib level (no module evaluation) to avoid
# the infinite recursion that arises when reading
# `config.configurations.nixos.<host>.module` back from a flake-level check.
#
# The portal parity check below runs at build time because CI evaluates every
# check's drvPath without building it before selecting runtime checks.
{ config, lib, ... }:
let
  baseline = config.flake.lib.nixos._commonAppsBaseline or { };
  baselinePrograms = baseline.programs or { };
  baselineServices = baseline.services or { };
  hostOverrides = config.flake.lib.nixos._hostAppsOverrides or { };
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
    hostOverrides != { }
    && ((baselinePrograms == { } && baselineServices == { }) || anyUnknownOverrides);
  baselineMissingMessage =
    if anyUnknownOverrides then
      "FR-5 baseline snapshot missing or out of sync: "
      + "flake.lib.nixos._commonAppsBaseline does not declare every entry in "
      + "flake.lib.nixos._hostAppsOverrides.<host>: "
      + unknownOverridesSummary
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

  noOpsByHost = lib.mapAttrs (_host: noOpsFor) hostOverrides;

  messageFor =
    host: noOps:
    "FR-5: ${host} apps-enable override duplicates common baseline (no-op). "
    + "Remove these entries from modules/${host}/apps-enable.nix: "
    + lib.concatStringsSep ", " noOps;

  portalPreferences = config.flake.lib.nixos._portalPreferences or null;
  portalInterfacesFor =
    backend:
    if portalPreferences == null then
      [ ]
    else
      builtins.filter (
        name:
        lib.hasPrefix "org.freedesktop.impl.portal." name
        && builtins.elem backend (lib.toList portalPreferences.${name})
      ) (builtins.attrNames portalPreferences);
  gtkPortalInterfaces = portalInterfacesFor "gtk";
  gnomeKeyringPortalInterfaces = portalInterfacesFor "gnome-keyring";
in
{
  perSystem =
    { pkgs, ... }:
    let
      portalInterfaceParity =
        {
          checkName,
          portalPackage,
          portalBasename,
          expectedInterfaces,
          exact,
        }:
        if expectedInterfaces == [ ] then
          throw "${checkName}: no portal interfaces are pinned to ${portalBasename}"
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
              printf '%s\n' "''${expected_interfaces[@]}" | sort -u > "$expected_file"
              sort -u "$actual_unsorted" > "$actual_file"

              if ${lib.boolToString exact}; then
                if ! cmp -s "$expected_file" "$actual_file"; then
                  echo "${checkName}: packaged ${portalBasename}.portal interfaces differ from pinned interfaces" >&2
                  echo "expected only / actual only:" >&2
                  comm -3 "$expected_file" "$actual_file" >&2
                  exit 1
                fi
              else
                missing_interfaces=$(comm -23 "$expected_file" "$actual_file")
                if [ -n "$missing_interfaces" ]; then
                  echo "${checkName}: packaged ${portalBasename}.portal is missing pinned interfaces:" >&2
                  printf '%s\n' "$missing_interfaces" >&2
                  exit 1
                fi
              fi

              printf 'ok: %s.portal Interfaces= satisfies %s pinned interfaces\n' "${portalBasename}" "${toString (builtins.length expectedInterfaces)}" > "$out"
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
              exact = true;
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
              exact = false;
            };
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
