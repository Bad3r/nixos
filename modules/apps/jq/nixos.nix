/*
  Package: jq
  Description: Lightweight and flexible command-line JSON processor.
  Homepage: https://jqlang.github.io/jq/
  Documentation: https://jqlang.github.io/jq/manual/
  Repository: https://github.com/jqlang/jq

  Summary:
    * Provides a functional programming language for querying, transforming, and generating JSON data streams.
    * Integrates easily into shell pipelines, supporting streaming, filtering, and complex transformations with concise expressions.

  Options:
    -c: Compact output by removing unnecessary whitespace.
    -r: Output raw strings instead of quoted JSON strings.
    -s: Slurp all inputs into an array before processing.
    -f <file>: Load filters from a file rather than command line.
    --arg/--argjson <name> <value>: Pass shell variables into jq programs.
*/
_:
let
  JqModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.jq.extended;
    in
    {
      options.programs.jq.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jq.";
        };

        package = lib.mkPackageOption pkgs "jq" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.jq = JqModule;
}
