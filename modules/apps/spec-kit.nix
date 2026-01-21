/*
  Package: spec-kit
  Description: GitHub's Spec-Kit for Spec-Driven Development with Claude Code.
  Homepage: https://github.com/github/spec-kit
  Documentation: https://github.github.io/spec-kit/
  Repository: https://github.com/github/spec-kit

  Summary:
    * Provides templates and slash commands for structured AI-assisted development workflows.
    * Includes specification, planning, task breakdown, and implementation phases.

  Options:
    spec-kit-init [TARGET_DIR]: Initialize a project with Spec-Kit templates.
    -f, --force: Overwrite existing template files.
    -h, --help: Show usage information.

  Example Usage:
    * `spec-kit-init` — Initialize current directory with Spec-Kit templates.
    * `spec-kit-init my-project` — Initialize a new project directory.
    * `spec-kit-init --force .` — Reinitialize, overwriting existing files.
*/
_:
let
  SpecKitModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."spec-kit".extended;
    in
    {
      options.programs."spec-kit".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable spec-kit.";
        };

        package = lib.mkPackageOption pkgs "spec-kit" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."spec-kit" = SpecKitModule;
}
