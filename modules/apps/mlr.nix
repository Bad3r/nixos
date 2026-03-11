/*
  Package: mlr
  Description: CLI toolkit for data operations over tabular key-value records.
  Homepage: https://github.com/johnkerl/miller
  Documentation: https://miller.readthedocs.io
  Repository: https://github.com/johnkerl/miller

  Summary:
    * Works like a streamable combination of awk, sed, cut, join, and sort over formats like CSV, JSON, and TSV.
    * Lets you chain verbs such as sort, filter, and stats1 into a single transformation pipeline.

  Options:
    cat: Output records without change.
    filter: Keep only records matching a predicate.
    sort: Order records by one or more keys.
    stats1: Compute one-pass numeric aggregates.
*/
_:
let
  MlrModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mlr.extended;
    in
    {
      options.programs.mlr.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mlr.";
        };

        package = lib.mkPackageOption pkgs "miller" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mlr = MlrModule;
}
