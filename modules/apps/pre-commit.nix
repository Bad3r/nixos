/*
  Package: pre-commit
  Description: Framework for managing and maintaining multi-language pre-commit hooks.
  Homepage: https://pre-commit.com/
  Documentation: https://pre-commit.com/#usage
  Repository: https://github.com/pre-commit/pre-commit

  Summary:
    * Manages git hooks with language-agnostic configuration via .pre-commit-config.yaml.
    * Runs linters, formatters, and validators automatically before commits across multiple languages.

  Options:
    install: Install git hook scripts into the repository.
    run [--all-files]: Execute hooks against staged files or all tracked files.
    autoupdate: Update hook revisions to the latest available version.
    uninstall: Remove pre-commit hooks from the repository.
*/
_:
let
  PreCommitModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."pre-commit".extended;
    in
    {
      options.programs."pre-commit".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pre-commit.";
        };

        package = lib.mkPackageOption pkgs "pre-commit" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."pre-commit" = PreCommitModule;
}
