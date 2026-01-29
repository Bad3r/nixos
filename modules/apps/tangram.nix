/*
  Package: tangram
  Description: Browser for pinned tabs that run as web applications.
  Homepage: https://github.com/sonnyp/Tangram
  Documentation: https://github.com/sonnyp/Tangram
  Repository: https://github.com/sonnyp/Tangram

  Summary:
    * Organizes web applications with persistent, independent tabs that maintain separate sessions and accounts.
    * Provides sandboxed browsing via WebKitGTK with smart notifications, downloads, and navigation gestures.

  Notes:
    * Part of GNOME Circle.
*/
_:
let
  TangramModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tangram.extended;
    in
    {
      options.programs.tangram.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tangram.";
        };

        package = lib.mkPackageOption pkgs "tangram" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tangram = TangramModule;
}
