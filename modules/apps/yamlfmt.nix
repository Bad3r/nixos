/*
  Package: yamlfmt
  Description: Extensible command line tool or library to format yaml files.
  Homepage: nil
  Documentation: https://github.com/google/yamlfmt/blob/main/docs/config-file.md
  Repository: https://github.com/google/yamlfmt

  Summary:
    * Formats YAML files from paths, globs, or stdin.
    * Supports config files, gitignore-aware excludes, dry runs, and lint mode.

  Options:
    -conf: Read yamlfmt config from a path.
    -dry: Show formatting output without writing changes.
    -gitignore_excludes: Use a gitignore file for excludes.
    -in: Format YAML from stdin.
    -lint: Check whether formatted output differs.
    -print_conf: Print the effective configuration.
*/
_:
let
  YamlfmtModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.yamlfmt.extended;
    in
    {
      options.programs.yamlfmt.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable yamlfmt.";
        };

        package = lib.mkPackageOption pkgs "yamlfmt" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.yamlfmt = YamlfmtModule;
}
