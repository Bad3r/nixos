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
    -e <glob>: Exclude files/directories matching glob patterns.
    -t <lang>: Filter to specific languages.
    -f <format>: Output in formats like `json`, `yaml`, `cbor`.
    --sort <category>: Sort results by lines, code, comments, etc.
*/
_:
let
  TokeiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tokei.extended;
    in
    {
      options.programs.tokei.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tokei.";
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
