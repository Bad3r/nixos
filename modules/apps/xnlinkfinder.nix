/*
  Package: xnlinkfinder
  Description: Endpoint, parameter, and target-specific wordlist discovery tool for web reconnaissance.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/xnl-h4ck3r/xnLinkFinder

  Summary:
    * Crawls URLs, raw files, archived Burp/ZAP/Caido exports, and HAR captures to extract links, JS-defined endpoints, and potential parameters.
    * Outputs deduplicated link, parameter, wordlist, and out-of-scope files alongside detected secrets (AWS keys, JWTs, GitHub tokens, private keys).

  Options:
    -i <input>: URL, URL list, directory, or Burp/ZAP/Caido/HAR file to inspect.
    -o <file>: Output path for discovered links (default `output.txt`; `cli` for stdout-only).
    -op <file>: Output path for potential parameters (default `parameters.txt`).
    -owl <file>: Output path for the target-specific wordlist (no wordlist by default).
    -os <file>: Output path for detected secrets (AWS, GitHub tokens, JWTs, private keys, etc.).
    -sp <domain|file>: Scope prefix used to expand relative `/` links to absolute URLs.
    -sf <domain|file>: Scope filter restricting accepted hosts during crawling.
    -d <depth>: Crawl depth when `-i` is a URL (paired with `-p` for concurrency).
    -H <"name: value">: Add custom request headers; repeat the flag to attach multiple.
    -inc: Include link source/context in the output for triage.
*/
_:
let
  XnlinkfinderModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xnlinkfinder.extended;
    in
    {
      options.programs.xnlinkfinder.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xnlinkfinder.";
        };

        package = lib.mkPackageOption pkgs "xnlinkfinder" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xnlinkfinder = XnlinkfinderModule;
}
