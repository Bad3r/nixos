/*
  Package: sourcemapper
  Description: Extract JavaScript source trees from Sourcemap files.
  Homepage: https://github.com/denandz/sourcemapper
  Documentation: https://github.com/denandz/sourcemapper#usage
  Repository: https://github.com/denandz/sourcemapper

  Summary:
    * Reconstructs original source trees from source map files produced by webpack and similar bundlers.
    * Can read generated JavaScript directly, follow `sourceMappingURL` references, and decode inline `data:` maps.

  Options:
    -url <path-or-url>: Read a local or remote source map file and extract its sources.
    -jsurl <url>: Fetch a JavaScript file first, then locate and process its source map reference.
    -output <dir>: Write reconstructed sources into the specified directory.
    -header <value>: Add request headers when fetching JavaScript or source maps over HTTP.
    -proxy <url>: Route outbound requests through the specified proxy.
    -insecure: Ignore invalid TLS certificates while downloading artifacts.
*/
_:
let
  SourcemapperModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sourcemapper.extended;
    in
    {
      options.programs.sourcemapper.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sourcemapper.";
        };

        package = lib.mkPackageOption pkgs "sourcemapper" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sourcemapper = SourcemapperModule;
}
