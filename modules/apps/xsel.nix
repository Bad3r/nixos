/*
  Package: xsel
  Description: Command-line program for manipulating X11 selections and clipboard.
  Homepage: https://github.com/kfish/xsel
  Documentation: https://github.com/kfish/xsel#readme
  Repository: https://github.com/kfish/xsel

  Summary:
    * Reads from and writes to X11 primary, secondary, and clipboard selections from shell scripts.
    * Enables piping data between terminal commands and graphical clipboard managers.

  Options:
    --clipboard: Target the clipboard selection instead of PRIMARY when paired with other flags.
    --input: Read from stdin (or a redirected file) and store the data in the chosen selection.
    --clear --primary: Clear the primary selection buffer before copying new content.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.xsel.extended;
  XselModule = {
    options.programs.xsel.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable xsel.";
      };

      package = lib.mkPackageOption pkgs "xsel" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.xsel = XselModule;
}
