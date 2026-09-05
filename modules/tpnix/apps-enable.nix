# Per-host overrides for tpnix. Entries here diverge from the common
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
# The same flat set is exposed via `flake.lib.nixos._hostAppsOverrides.tpnix`
# so `modules/hosts/common/checks.nix` can detect no-op overrides without
# re-evaluating module config.
{ config, ... }:
let
  appEnable = {
    azd = false;
    "azure-cli" = false;
    "cf-terraforming" = false;
    cloudflared = false;
    "coderabbit-cli" = false;
    discord = false;
    dropbox = false;
    dualsensectl = false;
    dwarfs = false; # Default dependency of steam extraTools
    ent = false;
    f3 = false;
    filezilla = false;
    "frida-tools" = false;
    ghidra = false;
    "gnome-disk-utility" = false;
    gnumake = false;
    gnused = false;
    gparted = false;
    hdparm = false;
    iotop = false;
    kdiskmark = false;
    "kiro-fhs" = false;
    lxsession = false;
    "maestral-gui" = false;
    markitdown = false;
    "minio-client" = false;
    mpv = false;
    "msgraph-cli" = false;
    onlyoffice-desktopeditors = false;
    opendirectorydownloader = false;
    parted = false;
    projectlibre = true;
    "spec-kit" = false;
    steam = false;
    terraform = false;
    thinkfan = true;
    upscayl = false;
    valgrind = false;
    "ventoy-full" = false;
    veracrypt = false;
    "video-cache" = false;
    vulnix = false;
    "xfce4-settings" = false;
    yarn = false;
  };

  # firefoxpwa.dmail is a per-site PWA sub-toggle, not a flat app: it routes to
  # dmail.enable, not extended.enable, so it cannot go through appEnable.
  # Registered so FR-5 compares it against the baseline too.
  subToggles = [
    {
      path = [
        "firefoxpwa"
        "dmail"
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
      "tpnix";
in
{
  flake.lib.nixos._hostAppsOverrides.tpnix = appEnable;
  flake.lib.nixos._hostAppsSubToggleOverrides.tpnix = subToggles;
  configurations.nixos.tpnix.module = {
    inherit (hostApps) programs services;
  };
}
