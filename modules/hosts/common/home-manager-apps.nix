{ config, lib, ... }:
let

  sharedAppNames = [
    "1password-gui-beta"
    "act"
    "antigravity-cli"
    "atuin"
    "autorandr"
    "bottom"
    "bun"
    "claude-code"
    "davmail"
    "direnv"
    "doom-emacs"
    "dunst"
    "element-desktop"
    "espanso"
    "flameshot"
    "gcc"
    "gemini-cli"
    "git"
    "go"
    "greenclip"
    "helix"
    "i3-config"
    "jq"
    "lazydocker"
    "lazygit"
    "less"
    "mpv"
    "nextcloud-client"
    "nixvim"
    "npm"
    "nushell"
    "onlyoffice-desktopeditors"
    "obsidian"
    "pentesting-devshell"
    "proton-drive"
    "rclone"
    "ripgrep"
    "rofi"
    "ruff"
    "skim"
    "starship"
    "stylix-gui"
    "tealdeer"
    "thunderbird"
    "tridactyl"
    "uv"
    "vscode"
    "wezterm"
    "yarn"
    "zathura"
    "zoxide"
  ];

  flakeHmApps = config.flake.homeManagerModules.apps;
  getAppModule =
    name:
    flakeHmApps.${name}
      or (throw "Home Manager app module '${name}' not found in flake.homeManagerModules.apps");

  # modules/home-manager/nixos.nix already imports these for the owner, and sharedModules imports
  # sharedAppNames too: a name in both evaluates its module twice, doubling list and `lines` options.
  repeatedAppNames = lib.intersectLists config.flake.lib.homeManager.defaultAppImports sharedAppNames;
  sharedAppModules =
    if repeatedAppNames == [ ] then
      map getAppModule sharedAppNames
    else
      throw "sharedAppNames repeats Home Manager apps that already load elsewhere, which evaluates their modules twice: ${lib.concatStringsSep ", " repeatedAppNames}";

  # Browsers register under flake.homeManagerModules.browsers (see
  # modules/browsers/); they are composed through sharedModules only because
  # home-manager.extraAppImports can resolve names from the apps namespace
  # alone.
  sharedBrowserNames = [
    "firefox"
    "firefoxpwa"
    "google-chrome"
    "librewolf"
    "ungoogled-chromium"
  ];

  flakeHmBrowsers = config.flake.homeManagerModules.browsers;
  getBrowserModule =
    name:
    flakeHmBrowsers.${name}
      or (throw "Home Manager browser module '${name}' not found in flake.homeManagerModules.browsers");
  sharedBrowserModules = map getBrowserModule sharedBrowserNames;

  body = {
    home-manager.extraAppImports = lib.mkAfter sharedAppNames;
    home-manager.sharedModules = lib.mkAfter (sharedAppModules ++ sharedBrowserModules);
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
