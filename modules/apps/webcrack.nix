/*
  Package: webcrack
  Description: Deobfuscate, unminify and unpack bundled JavaScript.
  Homepage: https://webcrack.netlify.app
  Documentation: https://webcrack.netlify.app/docs/guide
  Repository: https://github.com/j4k0xb/webcrack

  Summary:
    * Reverse obfuscator.io transformations and unminify JavaScript code.
    * Extract and unpack modules from webpack/browserify bundles.

  Options:
    -o, --output <path>: Output directory for bundled files.
    -f, --force: Overwrite output directory.
    -m, --mangle: Mangle variable names.
    --no-jsx: Do not decompile JSX.
    --no-unpack: Do not extract modules from the bundle.
    --no-deobfuscate: Do not deobfuscate the code.
    --no-unminify: Do not unminify the code.
*/

_: {
  flake.nixosModules.apps.webcrack =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.webcrack.extended;
    in
    {
      options.programs.webcrack.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable webcrack.";
        };

        package = lib.mkPackageOption pkgs "webcrack" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
