/*
  Package: zap
  Description: OWASP Zed Attack Proxy for manual and automated web application security testing.
  Homepage: https://www.zaproxy.org/
  Documentation: https://www.zaproxy.org/docs/
  Repository: https://github.com/zaproxy/zaproxy

  Summary:
    * Provides an intercepting proxy, active scanner, passive scanner, and scripting environment for web application testing.
    * Supports both desktop-driven workflows and headless API automation for CI or repeatable assessment pipelines.

  Options:
    zap: Launch the desktop proxy and scanning interface.
    -daemon: Start ZAP headlessly for API-driven automation or proxied testing.
    -addoninstall <id>: Install an add-on from the ZAP marketplace into the current profile.
*/
_:
let
  ZapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zap.extended;
    in
    {
      options.programs.zap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable zap.";
        };

        package = lib.mkPackageOption pkgs "zap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.zap = ZapModule;
}
