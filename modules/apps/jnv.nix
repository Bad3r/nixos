/*
  Package: jnv
  Description: Interactive CLI JSON viewer and jq playground built with TUI controls.
  Homepage: https://github.com/ynqa/jnv
  Documentation: https://github.com/ynqa/jnv#usage
  Repository: https://github.com/ynqa/jnv

  Summary:
    * Provides a curses-based interface for exploring JSON documents and crafting jq filters with live previews.
    * Ideal for debugging APIs or log payloads, with support for loading files or piping data via stdin.

  Options:
    -c, --config <file>: Use a specific configuration file.
    --default-filter <filter>: Apply a jq filter when the interface first loads.
    --write-to-stdout: Write the current JSON result to stdout on exit.
*/
_:
let
  JnvModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.jnv.extended;
    in
    {
      options.programs.jnv.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jnv.";
        };

        package = lib.mkPackageOption pkgs "jnv" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.jnv = JnvModule;
}
