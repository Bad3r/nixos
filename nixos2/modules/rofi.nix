# modules/rofi.nix

# TODO: Update to use rofi-run
{ lib, ... }:
{
  flake.modules.homeManager.base =
    {
      pkgs,
      config,
      ...
    }:
    let
      rofi-type = pkgs.writeShellScript "rofi-type" ''
        CMD=$(${lib.getExe config.programs.rofi.package} -dmenu -p '   ')
        echo "type $($CMD)" | ${config.dotoolc}
      '';

      mod = config.xsession.windowManager.i3.config.modifier;
    in
    {
      xsession.windowManager.i3.config.keybindings."--no-repeat ${mod}+t" = "exec ${rofi-type}";
    };
}
