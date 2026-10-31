/*
  Package: deadnix
  Description: Detects unused let-bindings and function parameters in Nix expressions.
  Homepage: https://github.com/astro/deadnix
  Documentation: https://github.com/astro/deadnix#usage
  Repository: https://github.com/astro/deadnix

  Summary:
    * Reports dead code and can remove it in place.
    * Emits JSON for editors and CI.

  Options:
    deadnix -e: Remove unused code from the source files.
    deadnix -f: Exit 1 when unused code is found.
    deadnix -o json: Emit machine-readable reports.
*/
_:
let
  DeadnixModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.deadnix.extended;
    in
    {
      options.programs.deadnix.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable deadnix.";
        };

        package = lib.mkPackageOption pkgs "deadnix" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.deadnix = DeadnixModule;
}
