# Per-host overrides for tpnix. Entries here diverge from the common
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
# The same flat set is exposed via `flake.lib.nixos._hostAppsOverrides.tpnix`
# so `modules/hosts/common/checks.nix` can detect no-op overrides without
# re-evaluating module config.
{ config, lib, ... }:
let
  appEnable = {
    "antigravity-fhs" = false;
    azd = false;
    "azure-cli" = false;
    "cf-terraforming" = false;
    cloudflared = false;
    "coderabbit-cli" = false;
    "czkawka-cli" = false;
    "czkawka-gui" = false;
    discord = false;
    dropbox = false;
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
    maestral = false;
    "maestral-gui" = false;
    "minio-client" = false;
    mpv = false;
    "msgraph-cli" = false;
    "mullvad-browser" = false;
    nodejs_22 = false;
    "oh-my-opencode" = false;
    onlyoffice-desktopeditors = false;
    opendirectorydownloader = false;
    parted = false;
    "spec-kit" = false;
    steam = false;
    terraform = false;
    upscayl = false;
    valgrind = false;
    "ventoy-full" = false;
    veracrypt = false;
    "video-cache" = false;
    vulnix = false;
    "xfce4-settings" = false;
    yarn = false;
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
  flake.lib.nixos._hostAppsOverrides.tpnix = appEnable;
  configurations.nixos.tpnix.module = {
    programs = lib.mapAttrs mkExtendedEnable programOverrides;
    services = lib.mapAttrs mkExtendedEnable serviceOverrides;
  };
}
