{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 CLI applications.")
      config;

  appNames = [
    "atuin"
    "dragon-drop"
    "kitty"
    "cosmic-term"
    "bottom"
    "htop"
    "sysstat"
    "direnv"
    "nix-direnv"
    "tealdeer"
    "xclip"
    "xsel"
    "starship"
    "zoxide"
  ];

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);
in
{
  configurations.nixos.system76.module.imports = getApps appNames;
}
