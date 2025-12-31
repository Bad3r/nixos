/*
  Package: lefthook
  Description: Fast and powerful Git hooks manager for any type of projects.
  Homepage: https://lefthook.dev/
  Documentation: https://lefthook.dev/usage/commands.html
  Repository: https://github.com/evilmartians/lefthook

  Summary:
    * Configures and runs pre-commit, commit-msg, and other Git hooks via YAML-based definitions.
    * Executes hook commands in parallel with support for scripts, globs, and environment customization.

  Options:
    install: Install configured hooks to the Git project.
    run <hook>: Execute a specific hook manually; use --all-files to run on all files.
    add <hook>: Register a new hook; use --dirs to create hook directory.
    uninstall: Remove hooks installed by lefthook.
*/
_:
let
  LefthookModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lefthook.extended;
    in
    {
      options.programs.lefthook.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable lefthook.";
        };

        package = lib.mkPackageOption pkgs "lefthook" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lefthook = LefthookModule;
}
