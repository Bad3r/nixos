/*
  Package: actionlint
  Description: Static checker for GitHub Actions workflow files.
  Homepage: https://rhysd.github.io/actionlint/
  Documentation: https://github.com/rhysd/actionlint/blob/main/docs/usage.md
  Repository: https://github.com/rhysd/actionlint

  Summary:
    * Lints GitHub Actions workflow syntax, expressions, and runner configuration.
    * Integrates with shellcheck and pyflakes to validate embedded scripts.

  Options:
    -config-file: Read configuration from a specific file path.
    -format: Render diagnostics with a custom Go template (for JSON or machine output).
    -ignore: Ignore findings matching a regular expression (repeatable).
    -oneline: Emit one diagnostic per line for editor and CI tooling.
    -shellcheck: Override or disable shellcheck integration.
*/
_:
let
  ActionlintModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.actionlint.extended;
    in
    {
      options.programs.actionlint.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable actionlint.";
        };

        package = lib.mkPackageOption pkgs "actionlint" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.actionlint = ActionlintModule;
}
