# hosts/linux/system76/packages.nix
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    system76-power
    system76-wallpapers
    system76-scheduler
    system76-firmware

    # GUI
    tor-browser
    electron-mail
    mpv
    mpvScripts.thumbfast
    mpv-shim-default-shaders # https://github.com/iwalton3/default-shader-pack
    mpvScripts.mpv-cheatsheet # USAGE: Press '?' in mpv
    open-in-mpv # Browser extension to open links in mpv
    jellyfin-mpv-shim # Jellyfin media server integration

    marktext
    code-cursor
    vscode-fhs
    brave
    mattermost-desktop
    obsidian

    # cli
    exiftool
    tor
    biome
    gpg-tui
    gopass
    binutils
    coreutils
    gcc
    gnumake
    nodejs_22
    yarn
    openjdk
    clojure
    clojure-lsp
  ];
  #   chaotic.linuxPackages_cachyos.enable = true;
}
