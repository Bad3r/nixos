# Per-host overrides for tpnix. Entries here diverge from the common
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
# The same flat set is exposed via `flake.lib.nixos._hostAppsOverrides.tpnix`
# so `modules/hosts/common/checks.nix` can detect no-op overrides without
# re-evaluating module config.
{ config, ... }:
let
  appEnable = {
    antimicrox = false;
    "cloudflare-warp" = true;
    cloudflared = false;
    dropbox = false;
    dualsensectl = false;
    dwarfs = false;
    ent = false;
    f3 = false;
    filezilla = false;
    freerdp = true;
    "frida-tools" = false;
    ghidra = false;
    "gnome-disk-utility" = false;
    gnumake = false;
    gparted = false;
    hdparm = false;
    iotop = false;
    kdiskmark = false;
    "kiro-fhs" = false;
    libsecret = true;
    "maestral-gui" = false;
    markitdown = false;
    mpv = false;
    "nextcloud-client" = true;
    onlyoffice-desktopeditors = false;
    opendirectorydownloader = false;
    parted = false;
    projectlibre = true;
    "spec-kit" = false;
    steam = false;
    thinkfan = true;
    upscayl = false;
    valgrind = false;
    "ventoy-full" = false;
    veracrypt = false;
    "video-cache" = false;
    "virt-manager" = true;
    vulnix = false;
    winapps = true;
    yarn = false;
  };

  # firefoxpwa.dmail is a per-site PWA sub-toggle, not a flat app: it routes to
  # dmail.enable, not extended.enable, so it cannot go through appEnable.
  # disableGpuCompositing is a Logseq sub-option in the same shape; tpnix is
  # the PRIME sync host (modules/hosts/tpnix/power.nix), the condition the
  # workaround exists for. Registered so FR-5 compares them against the
  # baseline too.
  subToggles = [
    {
      path = [
        "firefoxpwa"
        "dmail"
        "enable"
      ];
      value = true;
    }
    {
      path = [
        "logseq"
        "extended"
        "disableGpuCompositing"
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
