/*
  Package: curl
  Description: Command-line tool and library for transferring data with URL syntax.
  Homepage: https://curl.se/
  Documentation: https://curl.se/docs/manual.html
  Repository: https://github.com/curl/curl

  Summary:
    * Supports HTTP(S), FTP, SFTP, and numerous other protocols with granular control over TLS and authentication.
    * Powers automation and scripting workflows via libcurl bindings and flexible output formatting.

  Options:
    -I <url>: Fetch only HTTP response headers for quick health checks.
    -d @file: POST data from a file, often paired with `--header 'Content-Type: application/json'`.
    --retry 3 --fail: Retry transient failures while still exiting non-zero on HTTP error codes.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.curl.extended;
  CurlModule = {
    options.programs.curl.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable curl.";
      };

      package = lib.mkPackageOption pkgs "curl" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.curl = CurlModule;
}
