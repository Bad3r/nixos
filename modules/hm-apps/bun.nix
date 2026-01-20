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
_: {
  flake.homeManagerModules.apps.bun =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "bun" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.bun = {
          enable = true;
          # NOTE: Cannot use `package = null` here because enableGitIntegration
          # requires the package reference to configure git diff for bun.lockb.
          # HM uses `lib.getExe cfg.package` to set up the textconv filter.
          # This means bun is installed via both NixOS (environment.systemPackages)
          # and HM (home.packages), but both point to the same store path.
          enableGitIntegration = true;
        };
      };
    };
}
