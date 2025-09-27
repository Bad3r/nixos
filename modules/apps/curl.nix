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
  flake.nixosModules.apps.curl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curl ];
    };
}
