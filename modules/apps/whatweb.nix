/*
  Package: whatweb
  Description: Web technology fingerprinting scanner for identifying frameworks, CMSes, and infrastructure components.
  Homepage: nil
  Documentation: https://github.com/urbanadventurer/whatweb/wiki
  Repository: https://github.com/urbanadventurer/whatweb

  Summary:
    * Fingerprints websites with plugin-based detections for servers, frameworks, analytics, and CMS technologies.
    * Supports quiet and structured output modes for reconnaissance pipelines and reporting.

  Options:
    -a <level>: Increase probing aggression from passive fingerprinting to deeper active checks.
    --log-json <file>: Write findings as JSON for later analysis.
    --no-errors: Suppress transient HTTP and parsing errors during large scans.
*/
_:
let
  WhatwebModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.whatweb.extended;
    in
    {
      options.programs.whatweb.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable whatweb.";
        };

        package = lib.mkPackageOption pkgs "whatweb" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.whatweb = WhatwebModule;
}
