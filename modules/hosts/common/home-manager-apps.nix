{ config, lib, ... }:
let

  sharedAppNames = [
    "1password-gui-beta"
    "act"
    "antigravity-cli"
    "atuin"
    "autorandr"
    "bat"
    "bottom"
    "bun"
    "claude-code"
    "dive"
    "docker-compose"
    "doom-emacs"
    "element-desktop"
    "espanso"
    "fd"
    "feh"
    "file-roller"
    "flameshot"
    "fzf"
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
    "keepassxc"
    "kitty"
    "lazydocker"
    "lazygit"
    "less"
    "lutris"
    "mpv"
    "ncdu"
    "nixvim"
    "nushell"
    "onlyoffice-desktopeditors"
    "obsidian"
    "pandoc"
    "pcmanfm"
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
    "tree"
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
  sharedAppModules = map getAppModule sharedAppNames;

  # Browsers register under flake.homeManagerModules.browsers (see
  # modules/browsers/); they are composed through sharedModules only because
  # home-manager.extraAppImports can resolve names from the apps namespace
  # alone.
  sharedBrowserNames = [
    "firefox"
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

  body = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter sharedAppNames;
      home-manager.sharedModules = lib.mkAfter (sharedAppModules ++ sharedBrowserModules);
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
