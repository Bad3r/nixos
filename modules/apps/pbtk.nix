/*
  Package: pbtk
  Description: Toolset for reverse engineering and fuzzing Protobuf-based apps.
  Homepage: https://github.com/marin-m/pbtk
  Documentation: https://github.com/marin-m/pbtk#readme
  Repository: https://github.com/marin-m/pbtk

  Summary:
    * Extracts `.proto` definitions from APK, JAR, and DEX files and from binaries that embed Protobuf reflection metadata.
    * Edits, replays, and fuzzes Protobuf messages sent to network endpoints through a GTK 4 interface.
*/
_:
let
  PbtkModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pbtk.extended;
    in
    {
      options.programs.pbtk.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pbtk.";
        };

        package = lib.mkPackageOption pkgs "pbtk" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  # The bundled Jad decompiler is unfree.
  nixpkgs.allowedUnfreePackages = [ "pbtk" ];
  flake.nixosModules.apps.pbtk = PbtkModule;
}
