/*
  Package: katana
  Description: Next-generation crawling and spidering framework for endpoint discovery.
  Homepage: https://github.com/projectdiscovery/katana
  Documentation: https://docs.projectdiscovery.io/tools/katana
  Repository: https://github.com/projectdiscovery/katana

  Summary:
    * Crawls web applications in standard and headless (JavaScript-aware) modes to enumerate endpoints, parameters, and assets.
    * Slots into the ProjectDiscovery pipeline downstream of subfinder, dnsx, and httpx for end-to-end recon.

  Options:
    -u, -list <target>: Target URL or host to crawl (repeatable or file input).
    -headless: Enable headless-browser crawling for JavaScript-rendered content.
    -jc, -js-crawl: Parse and crawl endpoints discovered inside JavaScript files.
    -d, -depth <n>: Maximum crawl depth.
    -kf, -known-files <value>: Crawl well-known files such as robots.txt and sitemap.xml.
    -fs, -field-scope <value>: Restrict crawl scope by field (rdn, fqdn, dn).
    -o, -output <file>: Write output to the specified file.
    -jsonl: Emit JSON-line output for downstream tooling.
*/
_:
let
  KatanaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.katana.extended;
    in
    {
      options.programs.katana.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable katana.";
        };

        package = lib.mkPackageOption pkgs "katana" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.katana = KatanaModule;
}
