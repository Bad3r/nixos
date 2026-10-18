/*
  Package: wakaru
  Description: Javascript decompiler for modern frontend.
  Homepage: https://wakaru.vercel.app/
  Documentation: https://github.com/pionxzh/wakaru#readme
  Repository: https://github.com/pionxzh/wakaru

  Summary:
    * Unpacks bundled JavaScript into separated modules from webpack and browserify.
    * Unminifies transpiled code from Terser, Babel, SWC, and TypeScript.

  Options:
    -o, --output: Specify the output directory (default: out/).
    -f, --force: Force overwrite output directory.
    --concurrency: Maximum number of concurrent tasks (default: 1).
    --perf: Show performance statistics.
*/

_: {
  flake.nixosModules.apps.wakaru =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wakaru.extended;
    in
    {
      options.programs.wakaru.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wakaru.";
        };

        package = lib.mkPackageOption pkgs "wakaru" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
