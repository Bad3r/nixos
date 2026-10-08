/*
  Package: assetripper
  Description: Tool for extracting assets from Unity serialized files and asset bundles.
  Homepage: https://github.com/AssetRipper/AssetRipper
  Documentation: https://assetripper.github.io/AssetRipper/
  Repository: https://github.com/AssetRipper/AssetRipper

  Summary:
    * Analyzes Unity serialized files and asset bundles.
    * Reconstructs assets in the native Unity project format.

  Options:
    GUI: Launch AssetRipper and open Unity game folders or asset files.
*/
_:
let
  AssetRipperModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.assetripper.extended;
    in
    {
      options.programs.assetripper.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable assetripper.";
        };

        package = lib.mkPackageOption pkgs "assetripper" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.assetripper = AssetRipperModule;
}
