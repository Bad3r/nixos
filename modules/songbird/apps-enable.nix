# Per-host overrides for songbird. Entries here diverge from the common
# baseline in modules/hosts/common/apps-enable.nix.
#
# Priority: the common baseline uses `lib.mkOverride 1100` (low priority).
# The builder applies these at `lib.mkOverride 1000` so the per-host override
# wins over the common baseline at evaluation time while still permitting
# normal user overrides at default priority (100).
#
# `appEnable` is a flat override list. Entries are routed to
# `programs.<name>.extended.enable` or `services.<name>.extended.enable` based
# on the namespace where the common baseline declares the app.
#
# The same flat set is exposed via `flake.lib.nixos._hostAppsOverrides.songbird`
# so `modules/hosts/common/checks.nix` can detect no-op overrides without
# re-evaluating module config.
{ config, ... }:
let
  appEnable = {
    inkscape = true;
  };

  # Nested toggles cannot go through appEnable, which routes every entry to a
  # fixed extended.enable. Registered here so FR-5 compares them against the
  # baseline too.
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
  # Built from the registries above, never written out here, so an
  # unregistered override cannot exist and the write side cannot disagree with
  # the FR-5 comparison about which namespace a path belongs to.
  hostApps =
    (config.flake.lib.hostApps.mk
      or (throw "modules/hosts/common/checks.nix no longer exports flake.lib.hostApps.mk")
    )
      "songbird";
in
{
  flake.lib.nixos._hostAppsOverrides.songbird = appEnable;
  flake.lib.nixos._hostAppsSubToggleOverrides.songbird = subToggles;
  configurations.nixos.songbird.module = {
    # Logseq keeps normal GPU compositing here: the disableGpuCompositing
    # override in modules/system76/apps-enable.nix is a PRIME sync workaround
    # and this is a single-GPU desktop.
    inherit (hostApps) programs services;
  };
}
