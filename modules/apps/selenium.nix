/*
  Package: selenium
  Description: Python WebDriver bindings for browser automation and remote browser control.
  Homepage: https://www.selenium.dev/
  Documentation: https://www.selenium.dev/documentation/
  Repository: https://github.com/SeleniumHQ/selenium

  Summary:
    * Provides Python bindings for driving Chrome, Firefox, Edge, and remote WebDriver-compatible browser endpoints.
    * Includes Selenium Manager integration in the packaged bindings for locating or provisioning browser drivers on Linux.

  Options:
    webdriver.Chrome(): Launch and control a local Chrome session from Python.
    webdriver.Firefox(): Launch and control a local Firefox session from Python.
    webdriver.Remote(command_executor=<url>): Drive a remote Selenium-compatible Grid or browser service.

  Notes:
    * This module installs `python3Packages.selenium` rather than the legacy standalone server jar.
*/
_:
let
  SeleniumModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.selenium.extended;
    in
    {
      options.programs.selenium.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable selenium.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "selenium" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.selenium = SeleniumModule;
}
