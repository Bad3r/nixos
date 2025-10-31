/*
  Package: nodejs_22
  Description: Node.js 22.x runtime and npm package manager for building and running JavaScript/TypeScript applications.
  Homepage: https://nodejs.org/
  Documentation: https://nodejs.org/docs/latest-v22.x/api/
  Repository: https://github.com/nodejs/node

  Summary:
    * Installs the Node.js 22 runtime with npm for server-side JavaScript, tooling, and frontend build pipelines.
    * Supports ECMAScript modules, V8 JavaScript engine features, and native addon development via node-gyp.

  Options:
    node <script.js>: Execute JavaScript files with Node.js.
    node --experimental-strip-types: Enable new experimental TypeScript stripping (22 feature).
    npm <command>: Manage packages (install, run scripts, audits).
    corepack enable: Activate package managers like pnpm/yarn shipped with Node 22.

  Example Usage:
    * `node app.js` — Run a Node.js server or script entrypoint.
    * `npm init -y {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} npm install express` — Initialize a project and add dependencies.
    * `npx tsc` — Execute TypeScript compiler via npx using the Node 22 toolchain.
*/
_:
let
  Nodejs22Module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nodejs_22.extended;
    in
    {
      options.programs.nodejs_22.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable nodejs_22.";
        };

        package = lib.mkPackageOption pkgs "nodejs_22" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nodejs_22 = Nodejs22Module;
}
