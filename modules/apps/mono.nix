/*
  Package: mono
  Description: Cross platform, open source .NET development framework.
  Homepage: https://gitlab.winehq.org/mono/mono
  Documentation: https://www.mono-project.com/docs/
  Repository: https://gitlab.winehq.org/mono/mono

  Summary:
    * Executes managed assemblies using the ECMA CLI runtime.
    * Includes compiler and other tools for .NET development.

  Options:
    --runtime=VERSION: Select a later runtime version compatible with the assembly.
*/
_:
let
  MonoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mono.extended;
    in
    {
      options.programs.mono.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mono.";
        };

        package = lib.mkPackageOption pkgs "mono" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mono = MonoModule;
}
