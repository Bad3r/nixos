# Per-host overrides for songbird. Entries here diverge from the common
# baseline in modules/hosts/common/apps-enable.nix.
#
# Priority: the common baseline uses `lib.mkOverride 1100` (low priority).
# The builder applies these at `lib.mkOverride 1000` so the per-host override
# wins over the common baseline and over 1050 prerequisites.
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
    "cloudflare-warp" = true;
    assetripper = true;
    "protonmail-bridge" = true;
    lact = true;
    babashka = true;
    "clojure-cli" = true;
    "clojure-lsp" = true;
    leiningen = true;
    delve = true;
    discordo = true;
    go = true;
    "golangci-lint" = true;
    gopls = true;
    "rust-analyzer" = true;
    "rust-clippy" = true;
    rustc = true;
    rustfmt = true;
    # The Qt client gives way to the namespaced service, whose module
    # (qbittorrent-webui.nix) enables the Web UI handler together with the
    # service.
    qbittorrent = false;
    hopper = true;
    iaito = true;
    ilspycmd = true;
    imhex = true;
    jadx = true;
    "llama-cpp" = true;
    "qwen-code" = true;
    paperless = true;
    malimite = true;
    mono = true;
    "pentesting-devshell" = true;
    radare2 = true;
    rizin = true;
    inkscape = true;
    ytubic = true;
    stash = true;
    websocat = true;
    nvtop = true;
    orca = true;
    "podman-desktop" = true;
    sbx = true;
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
    inherit (hostApps) programs services;
  };
}
