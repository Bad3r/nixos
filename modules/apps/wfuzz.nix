/*
  Package: wfuzz
  Description: Web application fuzzer for content discovery, parameter testing, and brute force.
  Homepage: nil
  Documentation: https://wfuzz.readthedocs.io
  Repository: https://github.com/xmendez/wfuzz

  Summary:
    * Replaces FUZZ keywords in URLs, headers, and bodies using configurable payloads, encoders, and iterators.
    * Filters and matches by HTTP status, response size, and word/line counts to surface anomalies during web assessments.

  Options:
    -u <url>: Target URL containing one or more `FUZZ` keywords.
    -z <payload>: Payload definition (e.g. `file,wordlist.txt`, `range,1-100`, `list,a-b-c`).
    -w <file>: Wordlist payload shortcut (alias for `-z file,<file>`).
    -t <n>: Number of concurrent connections (default 10).
    -X <method>: HTTP method to use, including `FUZZ` for method fuzzing.
    --hc / --hl / --hh / --hs: Hide responses by status code, line count, word count, or size respectively.
    --sc / --sl / --sh / --ss: Show only responses matching the given status, line, word, or size criteria.
    -p <ip:port[:type]>: Route requests through one or more proxies (HTTP, SOCKS4, SOCKS5).
*/
_:
let
  WfuzzModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wfuzz.extended;
    in
    {
      options.programs.wfuzz.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wfuzz.";
        };

        package = lib.mkPackageOption pkgs "wfuzz" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.wfuzz = WfuzzModule;
}
