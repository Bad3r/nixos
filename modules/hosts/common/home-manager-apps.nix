{ config, lib, ... }:
let

  sharedAppNames = [
    "1password-gui-beta"
    "act"
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
    "firefox"
    "flameshot"
    "fzf"
    "gcc"
    "git"
    "go"
    "greenclip"
    "google-chrome"
    "gptfdisk"
    "htop"
    "i3-config"
    "jq"
    "keepassxc"
    "kitty"
    "lazydocker"
    "lazygit"
    "less"
    "librewolf"
    "lutris"
    "mpv"
    "ncdu"
    "nix-index"
    "nixvim"
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
    "tree"
    "ungoogled-chromium"
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

  body = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter sharedAppNames;
      home-manager.sharedModules = lib.mkAfter sharedAppModules;
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
