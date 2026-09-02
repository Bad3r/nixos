# Per-host overrides for system76. Entries here diverge from the common
# baseline in modules/hosts/common/apps-enable.nix.
#
# Priority: the common baseline uses `lib.mkOverride 1100` (low priority).
# This file uses `lib.mkOverride 1000` so the per-host override wins over
# the common baseline at evaluation time while still permitting normal
# user overrides at default priority (100).
#
# `appEnable` is a flat override list. Entries are routed to
# `programs.<name>.extended.enable` or `services.<name>.extended.enable` based
# on the namespace where the common baseline declares the app.
#
# The same flat set is exposed via `flake.lib.nixos._hostAppsOverrides.system76`
# so `modules/hosts/common/checks.nix` can detect no-op overrides without
# re-evaluating module config.
{ config, lib, ... }:
let
  appEnable = {
    inkscape = true;
  };

  baseline =
    config.flake.lib.nixos._commonAppsBaseline or {
      programs = { };
      services = { };
    };
  baselineServices = baseline.services or { };
  isService = name: lib.hasAttr name baselineServices;
  programOverrides = lib.filterAttrs (name: _value: !(isService name)) appEnable;
  serviceOverrides = lib.filterAttrs (name: _value: isService name) appEnable;
  mkExtendedEnable = _name: value: {
    extended.enable = lib.mkOverride 1000 value;
  };

  # disableGpuCompositing is a Logseq sub-option, not a flat app toggle, so it
  # cannot go through appEnable. Registered so FR-5 compares it against the
  # baseline too, and applied from this list rather than written out, so an
  # unregistered one cannot exist.
  subToggles = [
    {
      path = [
        "logseq"
        "extended"
        "disableGpuCompositing"
      ];
      value = true;
    }
  ];
  # Route each toggle by the namespace containing its full path, checking
  # programs first and falling back to services for services-only paths. A path
  # absent from both namespaces fails this evaluation, not only the FR-5 check.
  # Shared with the FR-5 comparison so the write and read sides cannot disagree
  # about which namespace a path belongs to or whether it is comparable.
  applySubToggles =
    (config.flake.lib.nixos._mkHostAppsSubToggleApply
      or (throw "modules/hosts/common/checks.nix no longer exports flake.lib.nixos._mkHostAppsSubToggleApply")
    )
      baseline
      subToggles;
in
{
  flake.lib.nixos._hostAppsOverrides.system76 = appEnable;
  flake.lib.nixos._hostAppsSubToggleOverrides.system76 = subToggles;
  configurations.nixos.system76.module = {
    programs = applySubToggles "programs" (lib.mapAttrs mkExtendedEnable programOverrides);
    services = applySubToggles "services" (lib.mapAttrs mkExtendedEnable serviceOverrides);
  };
}
