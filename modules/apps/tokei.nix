/*
  Package: tokei
  Description: Fast lines-of-code counter supporting multiple languages and output formats.
  Homepage: https://github.com/XAMPPRocky/tokei
  Documentation: https://github.com/XAMPPRocky/tokei#usage
  Repository: https://github.com/XAMPPRocky/tokei

  Summary:
    * Analyzes directory trees to report code, comment, and blank line statistics across many programming languages.
    * Generates reports in table, JSON, YAML, and other formats, making it suitable for dashboards or CI metrics.

  Options:
    tokei <path>: Count lines recursively within a path.
    -e <glob>: Exclude files/directories matching glob patterns.
    -t <lang>: Filter to specific languages.
    -f <format>: Output in formats like `json`, `yaml`, `cbor`.
    --sort <category>: Sort results by lines, code, comments, etc.

  Example Usage:
    * `tokei src/` — View LOC statistics for a source directory.
    * `tokei . -e target -e vendor` — Ignore build artifacts and vendor directories.
    * `tokei . -f json | jq '.Totals.code'` — Produce JSON output and extract total code lines with jq.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.tokei.extended;
  TokeiModule = {
    options.programs.tokei.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable tokei.";
      };

      package = lib.mkPackageOption pkgs "tokei" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.tokei = TokeiModule;
}
