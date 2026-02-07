/*
  Package: pnpm
  Description: Fast, disk space efficient package manager for Node.js.
  Homepage: https://pnpm.io/
  Documentation: https://pnpm.io/motivation
  Repository: https://github.com/pnpm/pnpm

  Summary:
    * Installs Node.js dependencies using a content-addressable store with hard links to save disk space.
    * Enforces strict dependency isolation preventing phantom dependency access.

  Options:
    install: Install all dependencies listed in package.json.
    add <pkg>: Add a dependency to the project.
    run <script>: Execute a script defined in package.json.
    dlx <pkg>: Fetch and run a package without installing it permanently.
*/
_:
let
  PnpmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pnpm.extended;
    in
    {
      options.programs.pnpm.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pnpm.";
        };

        package = lib.mkPackageOption pkgs "pnpm" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.pnpm = PnpmModule;
}
