/*
  Package: shellcheck
  Description: Shell script analysis tool.
  Homepage: https://www.shellcheck.net/
  Documentation: https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md
  Repository: https://github.com/koalaman/shellcheck

  Summary:
    * Analyzes sh and bash scripts for syntax issues, semantic pitfalls, portability problems, and style findings.
    * Emits diagnostics for editor, CI, and build integration through text, GCC, CheckStyle, diff, and JSON formats.

  Options:
    -a: Include warnings from sourced files.
    -e: Exclude specific warning codes from the report.
    -f: Select an output format such as gcc, json, diff, checkstyle, quiet, or tty.
    -o: Enable optional checks by name, or enable all optional checks.
    -P: Set source search paths for sourced files.
    -s: Specify the shell dialect, such as sh, bash, dash, ksh, or busybox.
    -S: Set the minimum severity to error, warning, info, or style.
    -x: Allow source statements to reference files outside the checked file set.
    --rcfile: Prefer a specific .shellcheckrc file over the default search.
*/
_:
let
  ShellcheckModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.shellcheck.extended;
    in
    {
      options.programs.shellcheck.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable shellcheck.";
        };

        package = lib.mkPackageOption pkgs "shellcheck" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.shellcheck = ShellcheckModule;
}
