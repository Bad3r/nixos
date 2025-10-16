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

{
  flake.nixosModules.apps."wine-tools" =
    { pkgs, lib, ... }:
    let
      protonCompatTool = pkgs."proton-ge-bin".steamcompattool;
      steamRunExe = lib.getExe pkgs."steam-run";
      protonRunScript = pkgs.writeShellApplication {
        name = "proton-run";
        runtimeInputs = with pkgs; [
          steam-run
          coreutils
        ];
        text = ''
          set -euo pipefail

          if [ "$#" -lt 1 ]; then
            echo "Usage: proton-run <program> [args...]" >&2
            exit 1
          fi

          default_prefix="''${XDG_DATA_HOME:-$HOME/.local/share}/proton-ge"
          compat_path="''${STEAM_COMPAT_DATA_PATH:-''${PROTON_RUN_PREFIX:-$default_prefix}}"
          mkdir -p "$compat_path"
          export STEAM_COMPAT_DATA_PATH="$compat_path"

          exec ${steamRunExe} ${protonCompatTool}/proton run "$@"
        '';
      };
      packages = with pkgs; [
        wine-staging
        winetricks
        wineWowPackages.stagingFull
        protonCompatTool
        protonRunScript
      ];
    in
    {
      environment.systemPackages = packages;
    };
}
