{ lib, ... }:
let
  body = {
    xdg = {
      menus.enable = true;
      mime.enable = true;
      # User-level ~/.config/mimeapps.list always overrides system-level
      # User units own session startup; this masks systemd-xdg-autostart-generator.
      # graphical-desktop.nix sets it true at normal priority.
      autostart.enable = lib.mkForce false;
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
