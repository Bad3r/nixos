/*
  Package: restringer
  Description: JavaScript deobfuscator with emphasis on reconstructing strings.
  Homepage: https://github.com/HumanSecurity/restringer
  Documentation: https://github.com/HumanSecurity/restringer#readme
  Repository: https://github.com/HumanSecurity/restringer

  Summary:
    * Deobfuscates JavaScript with 40+ modular deobfuscation components.
    * Supports obfuscator.io, Caesar Plus, and other common obfuscators.
    * Uses sandboxed code evaluation via isolated-vm for unsafe deobfuscation.

  Options:
    -h, --help: Show help message.
    -q, --quiet: Suppress output.
    -v, --verbose: Enable verbose logging.
    -o, --output: Output file path.
    -m, --max-iterations: Maximum number of iterations.
*/

_: {
  flake.nixosModules.apps.restringer =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.restringer.extended;
    in
    {
      options.programs.restringer.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable restringer.";
        };

        package = lib.mkPackageOption pkgs "restringer" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
