/*
  Package: curl
  Description: Command-line tool and library for transferring data with URL syntax.
  Homepage: https://curl.se/
  Documentation: https://curl.se/docs/manual.html
  Repository: https://github.com/curl/curl

  Summary:
    * Supports HTTP(S), FTP, SFTP, and many other protocols, with control over TLS and authentication.
    * Ships libcurl for use from programs and scripts.

  Options:
    -I <url>: Fetch only HTTP response headers for quick health checks.
    -d @file: POST data from a file, often paired with `--header 'Content-Type: application/json'`.
    --retry 3 --fail: Retry transient failures while still exiting non-zero on HTTP error codes.
*/
_:
let
  CurlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.curl.extended;
    in
    {
      options.programs.curl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable curl.";
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
