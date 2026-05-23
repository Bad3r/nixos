/*
  Package: shfmt
  Description: Shell parser and formatter.
  Homepage: https://github.com/mvdan/sh
  Documentation: https://pkg.go.dev/mvdan.cc/sh/v3/cmd/shfmt
  Repository: https://github.com/mvdan/sh

  Summary:
    * Formats shell programs and recursively discovers shell scripts in directories.
    * Supports Bash, POSIX shell, mksh, Bats, and zsh dialect selection.

  Options:
    -d: Print a diff when formatting differs.
    -f: Recursively find shell files.
    -i: Set indentation width.
    -l: List files whose formatting differs.
    -ln: Select the shell language dialect.
    -w: Write formatted output back to files.
*/
_:
let
  ShfmtModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.shfmt.extended;
    in
    {
      options.programs.shfmt.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable shfmt.";
        };

        package = lib.mkPackageOption pkgs "shfmt" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.shfmt = ShfmtModule;
}
