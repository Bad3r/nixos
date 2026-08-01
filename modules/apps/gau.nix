/*
  Package: gau
  Description: Fetch known URLs for a domain from third-party archive sources.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/lc/gau

  Summary:
    * Pulls historical and known URLs for a domain from the Wayback Machine, Common Crawl, Open Threat Exchange, and URLScan.
    * Emits pipeline-friendly URL lists for passive endpoint discovery and fuzzing input; pairs with the active katana crawler.

  Options:
    --providers <list>: Sources to query (wayback, commoncrawl, otx, urlscan).
    --subs: Include subdomains of the target domain.
    --blacklist <exts>: Skip URLs with the listed extensions.
    --fp: Collapse URLs that differ only in query-parameter values.
    --threads <n>: Number of worker threads.
    --json: Emit JSON output.
    --o <file>: Write results to the given file.
*/
_:
let
  GauModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gau.extended;
    in
    {
      options.programs.gau.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gau.";
        };

        package = lib.mkPackageOption pkgs "gau" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gau = GauModule;
}
