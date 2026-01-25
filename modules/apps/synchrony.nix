/*
  Package: synchrony
  Description: Simple deobfuscator for mangled or obfuscated JavaScript files.
  Homepage: https://deobfuscate.relative.im/
  Documentation: https://relative.github.io/synchrony
  Repository: https://github.com/relative/synchrony

  Summary:
    * Deobfuscates JavaScript files produced by javascript-obfuscator/obfuscator.io.
    * Supports automatic symbol renaming and custom deobfuscation configs.

  Options:
    -o, --output: Where to output deobfuscated file.
    -c, --config: Supply a custom deobfuscation config.
    --rename: Rename symbols automatically.
    -l, --loose: Enable loose parsing.
    --ecma-version: Set ECMA version for AST parser (default: latest).
    --sourceType: Source type for file (script, module, or both).
*/

_: {
  flake.nixosModules.apps.synchrony =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.synchrony.extended;
    in
    {
      options.programs.synchrony.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable synchrony.";
        };

        package = lib.mkPackageOption pkgs "synchrony" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
