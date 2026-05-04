/*
  Package: ffuf
  Description: Fast Go-based web fuzzer for content discovery, virtual host enumeration, and parameter brute-forcing.
  Homepage: https://ffuf.io
  Documentation: https://github.com/ffuf/ffuf/wiki
  Repository: https://github.com/ffuf/ffuf

  Summary:
    * Replaces `FUZZ` keywords in URLs, headers, and request bodies with high concurrency and minimal overhead.
    * Supports recursive discovery, multi-wordlist modes (clusterbomb, pitchfork, sniper), autocalibration, and replay through intercepting proxies.

  Options:
    -u <url>: Target URL containing one or more `FUZZ` keywords.
    -w <wordlist[:KEY]>: Wordlist payload, optionally bound to a custom keyword for multi-list runs.
    -mc <codes>: Match HTTP status codes (default 200-299,301,302,307,401,403,405,500).
    -fc <codes>: Filter HTTP status codes from results.
    -t <n>: Number of concurrent threads (default 40).
    -recursion: Recurse into matched paths; combine with `-recursion-depth`.
    -mode <strategy>: Multi-wordlist mode (clusterbomb, pitchfork, sniper).
    -e <ext1,ext2>: Extend the FUZZ keyword with the listed file extensions.
    -request <file>: Load a raw HTTP request file with FUZZ keywords; pair with `-request-proto`.
    -json: Emit newline-delimited JSON for downstream tooling.
    -x <proxy>: Send traffic through an HTTP or SOCKS5 proxy (e.g. `http://127.0.0.1:8080`).
*/
_:
let
  FfufModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ffuf.extended;
    in
    {
      options.programs.ffuf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ffuf.";
        };

        package = lib.mkPackageOption pkgs "ffuf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ffuf = FfufModule;
}
