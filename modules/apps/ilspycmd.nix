/*
  Package: ilspycmd
  Description: Command-line decompiler for .NET assemblies.
  Homepage: https://github.com/icsharpcode/ILSpy
  Documentation: https://github.com/icsharpcode/ILSpy/blob/master/ICSharpCode.ILSpyCmd/README.md
  Repository: https://github.com/icsharpcode/ILSpy

  Summary:
    * Decompiles .NET assemblies and can generate portable PDB files.
    * Emits source to stdout or writes a decompiled project to a directory.

  Example Usage:
    * `ilspycmd sample.dll` -- Decompile an assembly to stdout.
    * `ilspycmd -p -o decompiled sample.dll` -- Create a decompiled project.
*/
_:
let
  ILSpyCmdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ilspycmd.extended;
    in
    {
      options.programs.ilspycmd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ilspycmd.";
        };

        package = lib.mkPackageOption pkgs "ilspycmd" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ilspycmd = ILSpyCmdModule;
}
