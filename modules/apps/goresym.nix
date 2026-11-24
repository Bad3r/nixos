/*
  Package: goresym
  Description: Go symbol recovery tool.
  Homepage: https://github.com/mandiant/GoReSym
  Documentation: https://github.com/mandiant/GoReSym#readme
  Repository: https://github.com/mandiant/GoReSym

  Summary:
    * Recovers function names, types, file and line data, and build information from Go binaries, including stripped ones.
    * Provides the `GoReSym` command.
*/
_:
let
  GoresymModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.goresym.extended;
    in
    {
      options.programs.goresym.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable GoReSym.";
        };

        package = lib.mkPackageOption pkgs "goresym" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.goresym = GoresymModule;
}
