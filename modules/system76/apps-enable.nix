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
in
{
  flake.lib.nixos._hostAppsOverrides.system76 = appEnable;
  configurations.nixos.system76.module = {
    # `disableGpuCompositing` is a Logseq sub-option, not a flat app toggle,
    # so it stays out of `appEnable` and is layered directly at priority 1000.
    programs = lib.recursiveUpdate (lib.mapAttrs mkExtendedEnable programOverrides) {
      logseq.extended.disableGpuCompositing = lib.mkOverride 1000 true;
    };
    services = lib.mapAttrs mkExtendedEnable serviceOverrides;
  };
}
