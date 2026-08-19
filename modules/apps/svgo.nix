/*
  Package: svgo
  Description: Node.js tool for optimizing SVG files.
  Homepage: https://svgo.dev/
  Documentation: https://svgo.dev/docs/usage/
  Repository: https://github.com/svg/svgo

  Summary:
    * Removes redundant SVG metadata, comments, hidden elements, and default attributes without changing rendering.
    * Simplifies SVG paths and structure to reduce asset size in build and graphics pipelines.

  Options:
    <input> [<input> ...]: Optimize one or more SVG files.
    -o, --output <output> [<output> ...]: Write optimized files to the specified paths.
    -r, --recursive: Process SVG files recursively under a directory.
    -f, --folder <directory>: Set the directory containing SVG files to process.
    --config <path>: Load an SVGO configuration file.
    --help: Show advanced command-line usage.
*/
_:
let
  SvgoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.svgo.extended;
    in
    {
      options.programs.svgo.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable svgo.";
        };

        package = lib.mkPackageOption pkgs "svgo" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.svgo = SvgoModule;
}
