# Per-host overrides for songbird. Entries here diverge from the common
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
# The same flat set is exposed via `flake.lib.nixos._hostAppsOverrides.songbird`
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

  # Nested toggles cannot go through appEnable, which routes every entry to a
  # fixed extended.enable. Registered here so FR-5 compares them against the
  # baseline too, and applied from this list rather than written out, so an
  # unregistered one cannot exist.
  subToggles = [
    {
      path = [
        "claude-code"
        "extended"
        "installMethods"
        "bun"
        "enable"
      ];
      value = true;
    }
  ];
  # Route each toggle by the namespace its app lives in, the way appEnable's
  # entries are routed. Folding everything into programs would silently write a
  # services app's sub-toggle under programs.
  # Shared with the FR-5 comparison so the write and read sides cannot disagree
  # about which namespace a path belongs to.
  applySubToggles =
    namespace: base:
    (config.flake.lib.nixos._hostAppsSubToggleApply
      or (throw "modules/hosts/common/checks.nix no longer exports flake.lib.nixos._hostAppsSubToggleApply")
    )
      baseline
      namespace
      base
      subToggles;
in
{
  flake.lib.nixos._hostAppsOverrides.songbird = appEnable;
  flake.lib.nixos._hostAppsSubToggleOverrides.songbird = subToggles;
  configurations.nixos.songbird.module = {
    # Logseq keeps normal GPU compositing here: the disableGpuCompositing
    # override in modules/system76/apps-enable.nix is a PRIME sync workaround
    # and this is a single-GPU desktop.
    programs = applySubToggles "programs" (lib.mapAttrs mkExtendedEnable programOverrides);
    services = applySubToggles "services" (lib.mapAttrs mkExtendedEnable serviceOverrides);
  };
}
