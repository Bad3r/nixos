# Per-host overrides for tpnix. Entries here diverge from the common
# baseline in modules/hosts/common/apps-enable.nix.
#
# Priority: the common baseline uses `lib.mkOverride 1100` (low priority).
# This file uses `lib.mkOverride 1000` so the per-host override wins over
# the common baseline at evaluation time while still permitting normal
# user overrides at default priority (100).
#
# The `appEnable` attrset below is exposed via
# `flake.lib.nixos._hostAppsOverrides.tpnix` so `modules/hosts/common/checks.nix`
# can detect no-op overrides (entries that duplicate the common baseline)
# without re-evaluating module config.
{ lib, ... }:
let
  appEnable = {
    act = false;
    "antigravity-fhs" = false;
    azd = false;
    "azure-cli" = false;
    brave = false;
    "cf-terraforming" = false;
    circumflex = false;
    "claude-plugins" = false;
    "cloudflare-warp" = false;
    cloudflared = false;
    "coderabbit-cli" = false;
    "czkawka-cli" = false;
    "czkawka-gui" = false;
    ddrescue = false;
    discord = false;
    dmidecode = false;
    docker = false;
    dropbox = false;
    dust = false;
    dwarfs = false; # Default dependency of steam extraTools
    ent = false;
    f3 = false;
    filezilla = false;
    firefox = false;
    flarectl = false;
    fonttools = false;
    "frida-tools" = false;
    "fuse-overlayfs" = false;
    gawk = false;
    gdb = false;
    ghidra = false;
    "gnome-disk-utility" = false;
    gnumake = false;
    gnused = false;
    gparted = false;
    hdparm = false;
    hyperfine = false;
    iotop = false;
    jnv = false;
    just = false;
    karere = false;
    kcolorchooser = false;
    kdiskmark = false;
    "kiro-fhs" = false;
    lazydocker = false;
    librsvg = false;
    librewolf = false;
    "logseq-cli" = false;
    lxsession = false;
    maestral = false;
    "maestral-gui" = false;
    "minio-client" = false;
    mpv = false;
    "msgraph-cli" = false;
    "mullvad-browser" = false;
    nodejs_22 = false;
    nodejs_24 = false;
    "nomachine-client" = false;
    nrm = false;
    nvd = false;
    "oh-my-opencode" = false;
    onlyoffice-desktopeditors = false;
    opendirectorydownloader = false;
    pamixer = false;
    parted = false;
    patch = false;
    pixman = false;
    "pkg-config" = false;
    planify = false;
    playerctl = false;
    potrace = false;
    "prefetch-yarn-deps" = false;
    procps = false;
    pyyaml = false;
    raindrop = false;
    remmina = false;
    s5cmd = false;
    screenkey = false;
    "signal-desktop" = false;
    smartmontools = false;
    "spec-kit" = false;
    sqlite = false;
    steam = false;
    synchrony = false;
    "telegram-desktop" = false;
    terraform = false;
    tesseract = false;
    tokei = false;
    udiskie = false;
    upscayl = false;
    valgrind = false;
    "ventoy-full" = false;
    veracrypt = false;
    "video-cache" = false;
    vulnix = false;
    wgcf = false;
    "worker-build" = false;
    wpsoffice = false;
    wrangler = false;
    "xfce4-settings" = false;
    yaak = false;
    yarn = false;
  };
in
{
  flake.lib.nixos._hostAppsOverrides.tpnix = appEnable;
  configurations.nixos.tpnix.module = {
    programs = lib.mapAttrs (_name: value: {
      extended.enable = lib.mkOverride 1000 value;
    }) appEnable;
  };
}
