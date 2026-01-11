/*
  Package: yarn
  Description: Fast, reliable package manager for JavaScript projects (Classic Yarn 1.x).
  Homepage: https://classic.yarnpkg.com/
  Documentation: https://classic.yarnpkg.com/en/docs/
  Repository: https://github.com/yarnpkg/yarn

  Summary:
    * Provides deterministic dependency installs via lockfiles, offline caches, workspaces, and script execution for Node.js projects.
    * Integrates with npm registry by default but supports custom registries and mirrors.

  Options:
    yarn init [-y]: Initialize a new package.json.
    yarn add <pkg> [--dev]: Add dependencies (development or runtime).
    yarn install: Install dependencies respecting yarn.lock.
    yarn run <script>: Execute scripts defined in package.json.
    yarn workspaces run <script>: Run commands across all workspaces.

  Example Usage:
    * `yarn init -y {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} yarn add react` — Bootstrap a project and add React dependency.
    * `yarn install --frozen-lockfile` — Install dependencies exactly as specified in the lockfile.
    * `yarn workspaces run test` — Run the `test` script across all monorepo workspaces.
*/
_:
let
  YarnModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.yarn.extended;
    in
    {
      options.programs.yarn.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable yarn.";
        };

        package = lib.mkPackageOption pkgs "yarn" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.yarn = YarnModule;
}
