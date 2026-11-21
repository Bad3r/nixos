/*
  Package: geckodriver
  Description: WebDriver proxy that drives Firefox-based browsers over Marionette.
  Homepage: https://github.com/mozilla/geckodriver
  Documentation: https://firefox-source-docs.mozilla.org/testing/geckodriver/
  Repository: https://github.com/mozilla/gecko-dev

  Summary:
    * Translates W3C WebDriver requests from Selenium-style clients into Marionette commands.
    * Is the driver the Firefox MCP server starts for every Camoufox or Firefox session.

  Notes:
    * Off by default; the agent MCP catalog turns its row on where the firefox server exists.
*/
_:
let
  GeckodriverModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.geckodriver.extended;
    in
    {
      options.programs.geckodriver.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable geckodriver.";
        };

        package = lib.mkPackageOption pkgs "geckodriver" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.geckodriver = GeckodriverModule;
}
