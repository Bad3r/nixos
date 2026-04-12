/*
  Package: source-map-explorer
  Description: Analyze and debug JavaScript bundle size through source maps.
  Homepage: https://github.com/danvk/source-map-explorer
  Documentation: https://github.com/danvk/source-map-explorer#readme
  Repository: https://github.com/danvk/source-map-explorer

  Summary:
    * Breaks minified bundles down by original source files and renders an interactive treemap.
    * Emits HTML, JSON, or TSV reports to inspect mapped, unmapped, and gzip-adjusted bundle size.

  Options:
    --json: Write report data as JSON instead of opening the treemap in a browser.
    --html: Write the treemap HTML to stdout or a file.
    --tsv: Write the breakdown as tab-separated values.
    -m, --only-mapped: Exclude unmapped bytes from totals and reports.
    --coverage: Colorize the treemap with Chrome coverage export data.
    --gzip: Calculate gzip size and imply `--only-mapped`.
*/
_:
let
  SourceMapExplorerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."source-map-explorer".extended;
    in
    {
      options.programs.source-map-explorer.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable source-map-explorer.";
        };

        package = lib.mkPackageOption pkgs "source-map-explorer" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.source-map-explorer = SourceMapExplorerModule;
}
