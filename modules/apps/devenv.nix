/*
  Package: devenv
  Description: Declarative development environments for local projects.
  Homepage: https://devenv.sh
  Documentation: https://devenv.sh/getting-started/
  Repository: https://github.com/cachix/devenv

  Summary:
    * Defines reproducible development environments with Nix and a single `devenv.nix` entrypoint.
    * Provides a consistent workflow for shells, services, tasks, and language tooling.

  Options:
    init: Initialize a project with a starter `devenv.nix`.
    shell: Enter the project development shell defined by `devenv.nix`.
    up: Run background services and processes declared in the environment.
    test: Execute integration checks configured for the project environment.
*/
_:
let
  DevenvModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.devenv.extended;
    in
    {
      options.programs.devenv.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable devenv.";
        };

        package = lib.mkPackageOption pkgs "devenv" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.devenv = DevenvModule;
}
