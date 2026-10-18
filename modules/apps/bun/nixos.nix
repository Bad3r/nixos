/*
  Package: bun
  Description: Incredibly fast JavaScript runtime, bundler, transpiler and package manager.
  Homepage: https://bun.sh
  Documentation: https://bun.sh/docs
  Repository: https://github.com/oven-sh/bun

  Summary:
    * All-in-one JavaScript/TypeScript toolkit combining runtime, bundler, test runner, and package manager.
    * Node.js-compatible drop-in replacement with significant speed improvements.

  Options:
    run: Execute scripts or files with watch/hot reload support.
    install: Install packages from npm with fast resolution.
    build: Bundle projects for browsers or other targets.
    test: Run tests with built-in test runner.
    --watch: Automatically restart on file changes.
    --hot: Enable hot module replacement.
    --smol: Use less memory with more frequent garbage collection.
*/
_:
let
  BunModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bun.extended;
    in
    {
      options.programs.bun.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bun.";
        };

        package = lib.mkPackageOption pkgs "bun" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bun = BunModule;
}
