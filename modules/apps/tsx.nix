/*
  Package: tsx
  Description: TypeScript Execute (tsx): The easiest way to run TypeScript in Node.js.
  Homepage: https://tsx.hirok.io/
  Documentation: https://tsx.hirok.io/getting-started
  Repository: https://github.com/privatenumber/tsx

  Summary:
    * Runs TypeScript files directly in Node.js with CommonJS and ESM interoperability.
    * Supports tsconfig paths, dependency-aware watch mode, shell scripts, and the Node.js test runner.

  Options:
    <file.ts>: Execute a TypeScript file with Node.js flags and script arguments.
    watch <file.ts>: Rerun a script whenever its dependencies change.
    --include <path>: Add files or directories to watch.
    --exclude <pattern>: Exclude files or directories from watch mode.
    --test: Run the Node.js test runner with TypeScript support.
*/
_:
let
  TsxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tsx.extended;
    in
    {
      options.programs.tsx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tsx.";
        };

        package = lib.mkPackageOption pkgs "tsx" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tsx = TsxModule;
}
