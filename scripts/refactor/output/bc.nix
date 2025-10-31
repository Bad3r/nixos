/*
  Package: bc
  Description: Arbitrary-precision calculator language for interactive and scripted math.
  Homepage: https://www.gnu.org/software/bc/
  Documentation: https://www.gnu.org/software/bc/manual/
  Repository: https://git.savannah.gnu.org/cgit/bc.git

  Summary:
    * Evaluates expressions with unlimited precision, user-defined functions, and control structures.
    * Runs in interactive REPL or batch mode, making it suitable for pipelines and automation.

  Options:
    -l: Load the standard math library with sine, cosine, and exponential functions.
    -q: Suppress the startup banner when entering interactive mode.
    -f <file>: Execute statements from the specified script file.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.bc.extended;
  BcModule = {
    options.programs.bc.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable bc.";
      };

      package = lib.mkPackageOption pkgs "bc" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.bc = BcModule;
}
