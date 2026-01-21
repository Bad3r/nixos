{ config, lib, ... }:
let
  extraAppNames = [
    "atuin"
    "autorandr"
    "bat"
    "bitwarden-desktop"
    "bottom"
    "bun"
    "claude-code"
    # "copyq"
    "dive"
    "docker-compose"
    "element-desktop"
    "espanso"
    # "evince"
    "fd"
    "feh"
    "file-roller"
    "firefox"
    "flameshot"
    "fzf"
    "floorp"
    "gcc"
    "git"
    "go"
    "google-chrome"
    "gptfdisk"
    "htop"
    "i3-config"
    "jq"
    "keepassxc"
    "kitty"
    "lazygit"
    "less"
    # "libreoffice"
    "lutris"
    "mpv"
    "ncdu"
    "nh"
    "nix-index"
    "nixvim"
    "obsidian"
    "pandoc"
    "pcmanfm"
    "pentesting-devshell"
    "rclone"
    "ripgrep"
    "ripgrep-all"
    "rofi"
    "ruff"
    "skim"
    # "slack"
    "sqlite"
    "starship"
    "stylix-gui"
    "tealdeer"
    "tree"
    "usbguard-notifier"
    "uv"
    # "vim" # Provided by nixvim (vimAlias = true)
    "vscode"
    "wezterm"
    "yarn"
    "zathura"
    "zoxide"
  ];

  # Access Home Manager app modules from the flake's registered modules
  # This allows modules to be defined anywhere in the codebase
  flakeHmApps = config.flake.homeManagerModules.apps;

  getAppModule =
    name:
    flakeHmApps.${name}
      or (throw "Home Manager app module '${name}' not found in flake.homeManagerModules.apps");

  extraAppModules = map getAppModule extraAppNames;
in
{
  configurations.nixos.system76.module = _: {
    config = {
      home-manager.extraAppImports = lib.mkAfter extraAppNames;
      home-manager.sharedModules = lib.mkAfter extraAppModules;
    };
  };
}
