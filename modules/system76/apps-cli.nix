{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

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
    "xkill"
    "starship"
    "zoxide"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps appNames;
}
