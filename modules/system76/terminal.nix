{ lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkBefore [ pkgs.kitty ];

      environment.variables.TERMINAL = lib.mkDefault "kitty";

      xdg.mime.defaultApplications = {
        "application/x-terminal-emulator" = lib.mkDefault "kitty.desktop";
        "x-scheme-handler/terminal" = lib.mkDefault "kitty.desktop";
      };
    };
}
