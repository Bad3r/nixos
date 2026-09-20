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
    "dive"
    "docker-compose"
    "doom-emacs"
    "dunst"
    "element-desktop"
    "espanso"
    "fd"
    "feh"
    "file-roller"
    "flameshot"
    "gcc"
    "gemini-cli"
    "git"
    "go"
    "greenclip"
    "gptfdisk"
    "helix"
    "htop"
    "i3-config"
    "jq"
    "lazydocker"
    "lazygit"
    "less"
    "lutris"
    "mpv"
    "ncdu"
    "nixvim"
    "npm"
    "nushell"
    "onlyoffice-desktopeditors"
    "obsidian"
    "pandoc"
    "pcmanfm"
    "proton-drive"
    "rclone"
    "remmina"
    "ripgrep"
    "ripgrep-all"
    "rofi"
    "ruff"
    "skim"
    "starship"
    "stylix-gui"
    "tealdeer"
    "thunderbird"
    "tridactyl"
    "usbguard-notifier"
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
  # the lists below too: a name in both evaluates its module twice, doubling list and `lines` options.
  defaultAppNames = config.flake.lib.homeManager.defaultAppImports;
  rejectLoadedTwice =
    listName: loadedElsewhere: names:
    let
      repeated = lib.intersectLists loadedElsewhere names;
    in
    if repeated == [ ] then
      names
    else
      throw "${listName} repeats Home Manager apps that already load elsewhere, which evaluates their modules twice: ${lib.concatStringsSep ", " repeated}";

  sharedAppModules = map getAppModule (
    rejectLoadedTwice "sharedAppNames" defaultAppNames sharedAppNames
  );

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

  # Host-only extras come from the registry:
  #   flake.lib.nixos.hosts.<host>.extraHomeApps = [ "<app>" ... ];
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  body =
    { hostName, ... }:
    let
      hostAppNames = (hostsRegistry.${hostName} or { }).extraHomeApps or [ ];
      hostAppModules = map getAppModule (
        rejectLoadedTwice "hosts.${hostName}.extraHomeApps" (defaultAppNames ++ sharedAppNames) hostAppNames
      );
    in
    {
      config = {
        home-manager.extraAppImports = lib.mkAfter (sharedAppNames ++ hostAppNames);
        home-manager.sharedModules = lib.mkAfter (
          sharedAppModules ++ sharedBrowserModules ++ hostAppModules
        );
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
