/*
  Package: wine-tools
  Description: Bundle of Wine utilities including wine-staging, winetricks, 32/64-bit Wine prefixes, Proton-GE, and a `proton-run` helper script.
  Homepage: https://www.winehq.org/
  Documentation: https://wiki.winehq.org/Wine_User%27s_Guide
  Repository: https://gitlab.winehq.org/wine/wine (Wine) / https://github.com/GloriousEggroll/proton-ge-custom (Proton-GE)

  Summary:
    * Installs the full Wine staging toolchain with both 32-bit and 64-bit support along with winetricks for dependency management.
    * Provides Proton-GE compatibility tool and a convenient `proton-run` script to run Windows applications using Proton outside Steam.

  Options:
    wine, wine64: Run Windows executables natively via Wine.
    winetricks <verb>: Install common DLLs or runtime components into a Wine prefix.
    proton-run <program> [args]: Execute Windows programs using Proton-GE with automatic prefix management.
    WINEPREFIX=<dir>: Target a specific Wine prefix directory.

  Example Usage:
    * `WINEPREFIX=~/prefixes/app wine setup.exe` — Install a Windows application into a custom prefix.
    * `winetricks corefonts vcrun2019` — Install required runtime components.
    * `proton-run game.exe` — Launch a program with Proton-GE’s compatibility enhancements.
*/
_:
let
  WineToolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."wine-tools".extended;
    in
    {
      options.programs."wine-tools".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Wine tools bundle (wine-staging, winetricks, proton-ge-bin).";
        };

        package = lib.mkPackageOption pkgs "proton-ge-bin" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cfg.package
          pkgs.wineWowPackages.staging
          pkgs.winetricks
        ];
      };
    };
in
{
  flake.nixosModules.apps."wine-tools" = WineToolsModule;
}
