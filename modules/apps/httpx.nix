/*
  Package: httpx
  Description: Fast HTTP toolkit for probing, enumeration, and web application reconnaissance.
  Homepage: https://github.com/projectdiscovery/httpx
  Documentation: https://docs.projectdiscovery.io/tools/httpx
  Repository: https://github.com/projectdiscovery/httpx

  Summary:
    * Performs high-speed HTTP probing with support for TLS info, status codes, technologies, CORS, content discovery, and more.
    * Integrates with ProjectDiscovery’s ecosystem by accepting stdin targets and emitting structured output suitable for pipelines.

  Options:
    -l <file>, -list <file>: Provide a list of hosts or URLs to probe.
    -H <header>: Add custom headers to requests (repeatable).
    -status-code, -tech-detect, -title: Enable additional modules to report status codes, detected technologies, or page titles.
    -json, -csv: Output results in machine-readable formats.
    -follow-redirects: Follow HTTP redirects during probing.
*/
_:
let
  HttpxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.httpx.extended;
    in
    {
      options.programs.httpx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable httpx.";
        };

        package = lib.mkPackageOption pkgs "httpx" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.httpx = HttpxModule;
}
