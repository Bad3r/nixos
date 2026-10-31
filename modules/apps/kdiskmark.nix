/*
  Package: kdiskmark
  Description: Qt-based disk benchmark inspired by CrystalDiskMark for Linux.
  Homepage: https://github.com/JonMagon/KDiskMark
  Documentation: https://github.com/JonMagon/KDiskMark#features
  Repository: https://github.com/JonMagon/KDiskMark

  Summary:
    * Measures sequential and random read/write performance with configurable profiles and queue depths.
    * Saves benchmark reports and displays results in a GUI.
*/
_:
let
  KdiskmarkModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.kdiskmark.extended;
    in
    {
      options.programs.kdiskmark.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable kdiskmark.";
        };

        package = lib.mkPackageOption pkgs "kdiskmark" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.kdiskmark = KdiskmarkModule;
}
