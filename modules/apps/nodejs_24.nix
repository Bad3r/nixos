/*
  Package: nodejs_24
  Description: Node.js 24.x runtime with npm and corepack for modern JavaScript/TypeScript development.
  Homepage: https://nodejs.org/
  Documentation: https://nodejs.org/docs/latest-v24.x/api/
  Repository: https://github.com/nodejs/node

  Summary:
    * Provides the cutting-edge Node.js release with updated V8 features, built-in test runner enhancements, and web-standard APIs.
    * Includes npm and corepack so alternative package managers (pnpm, yarn) can be enabled on demand.

  Options:
    node <file.mjs>: Run ECMAScript modules or scripts.
    node --test: Execute Node’s built-in test runner for the current project.
    npm exec <tool>: Execute binaries from dependencies via npm.
    corepack enable pnpm: Activate pinned pnpm versions shipped with Node 24.

  Example Usage:
    * `node --test` — Run tests using the built-in test runner infrastructure.
    * `npm create vite@latest my-app` — Scaffold a web project using the latest npm toolchains.
    * `corepack enable pnpm {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} pnpm install` — Switch to pnpm package management for the project.
*/
_:
let
  Nodejs24Module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nodejs_24.extended;
    in
    {
      options.programs.nodejs_24.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable nodejs_24.";
        };

        package = lib.mkPackageOption pkgs "nodejs_24" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nodejs_24 = Nodejs24Module;
}
