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
    proton-tricks <verb>: Install components into proton-run's prefix using Proton's Wine (respects PROTON_VERSION).
    proton-run <program> [args]: Execute Windows programs using Proton with automatic prefix management.
    WINEPREFIX=<dir>: Target a specific Wine prefix directory.
    PROTON_VERSION=<version>: Select which Proton version to use. Supports:
      - Third-party builds in compatibilitytools.d (e.g., 'GE-Proton9-20')
      - Official Steam versions in steamapps/common (e.g., 'Proton-Experimental', 'Proton-9.0')
      - Absolute paths to Proton installations
      Note: 'Proton-X' is automatically translated to 'Proton - X' for Steam's naming convention.

  Example Usage:
    * `WINEPREFIX=~/prefixes/app wine setup.exe` -- Install a Windows application into a custom prefix.
    * `winetricks corefonts vcrun2019` -- Install required runtime components.
    * `proton-run game.exe` -- Launch a program with Proton-GE's compatibility enhancements.
    * `PROTON_VERSION=Proton-Experimental proton-run game.exe` -- Use Steam's Proton Experimental.
    * `PROTON_VERSION=GE-Proton9-20 proton-run game.exe` -- Use a specific GE-Proton version.
    * `proton-tricks vcrun2022` -- Install VC++ 2022 runtime into proton-run's prefix.
    * `PROTON_VERSION=Proton-Experimental proton-tricks vcrun2022 dotnet48` -- Install runtimes using Proton Experimental's Wine.
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
      protonCompatTool = pkgs.proton-ge-bin.steamcompattool;
      # Custom steam-run with additional libraries for better compatibility
      customSteamRun =
        (pkgs.steam.override {
          extraPkgs =
            p: with p; [
              # Font rendering
              freetype
              fontconfig
              # Common runtime dependencies
              libgcc
              xorg.libX11
              xorg.libXcursor
              xorg.libXrandr
              xorg.libXi
              # Audio
              libpulseaudio
              alsa-lib
              # Graphics
              vulkan-loader
              # .NET/Mono support
              mono
            ];
        }).run;
      steamRunExe = lib.getExe customSteamRun;

      # Shared Proton detection logic (used by both proton-run and proton-tricks)
      protonDetectScript = ''
        # Default to Proton-GE from Nix
        proton_dir="${protonCompatTool}"

        # Allow overriding Proton version
        if [ -n "''${PROTON_VERSION:-}" ]; then
          found=0

          # If it's an absolute path, use it directly
          if [[ "$PROTON_VERSION" == /* ]]; then
            if [ -d "$PROTON_VERSION" ]; then
              proton_dir="$PROTON_VERSION"
              found=1
              echo "Using Proton from: $proton_dir" >&2
            else
              echo "Warning: PROTON_VERSION path '$PROTON_VERSION' not found, using default Proton-GE" >&2
            fi
          else
            # Third-party builds (compatibilitytools.d)
            compat_dirs=(
              "$HOME/.steam/root/compatibilitytools.d"
              "$HOME/.local/share/Steam/compatibilitytools.d"
            )
            # Official Steam Proton versions (steamapps/common)
            steam_common_dirs=(
              "$HOME/.steam/root/steamapps/common"
              "$HOME/.local/share/Steam/steamapps/common"
            )

            # First, try exact match in compatibilitytools.d (for GE-Proton, etc.)
            for compat_dir in "''${compat_dirs[@]}"; do
              if [ -d "$compat_dir/$PROTON_VERSION" ]; then
                proton_dir="$compat_dir/$PROTON_VERSION"
                found=1
                echo "Using Proton from: $proton_dir" >&2
                break
              fi
            done

            # If not found, try Steam's common directory (exact match)
            if [ "$found" -eq 0 ]; then
              for common_dir in "''${steam_common_dirs[@]}"; do
                if [ -d "$common_dir/$PROTON_VERSION" ]; then
                  proton_dir="$common_dir/$PROTON_VERSION"
                  found=1
                  echo "Using Proton from: $proton_dir" >&2
                  break
                fi
              done
            fi

            # If still not found, try Steam's naming convention (Proton-X -> Proton - X)
            if [ "$found" -eq 0 ]; then
              steam_name="''${PROTON_VERSION/Proton-/Proton - }"
              if [ "$steam_name" != "$PROTON_VERSION" ]; then
                for common_dir in "''${steam_common_dirs[@]}"; do
                  if [ -d "$common_dir/$steam_name" ]; then
                    proton_dir="$common_dir/$steam_name"
                    found=1
                    echo "Using Proton from: $proton_dir" >&2
                    break
                  fi
                done
              fi
            fi

            if [ "$found" -eq 0 ]; then
              echo "Warning: PROTON_VERSION '$PROTON_VERSION' not found, using default Proton-GE" >&2
              echo "Searched: compatibilitytools.d, steamapps/common" >&2
            fi
          fi
        fi

        # Set up prefix path (derive from Proton directory name if not overridden)
        proton_name="$(basename "$proton_dir" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
        default_prefix="''${XDG_DATA_HOME:-$HOME/.local/share}/proton-prefixes/$proton_name"
        compat_path="''${STEAM_COMPAT_DATA_PATH:-''${PROTON_RUN_PREFIX:-$default_prefix}}"
        mkdir -p "$compat_path"
        export STEAM_COMPAT_DATA_PATH="$compat_path"
        export WINEPREFIX="$compat_path/pfx"

        # Set Steam client install path (required by Proton)
        if [ -z "''${STEAM_COMPAT_CLIENT_INSTALL_PATH:-}" ]; then
          if [ -d "$HOME/.steam/root" ]; then
            export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/root"
          elif [ -d "$HOME/.local/share/Steam" ]; then
            export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
          else
            echo "Warning: Steam installation not found, some features may not work" >&2
            export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/root"
          fi
        fi
      '';

      protonTricksScript = pkgs.writeShellApplication {
        name = "proton-tricks";
        runtimeInputs = [
          customSteamRun
          pkgs.coreutils
          pkgs.winetricks
        ];
        text = /* bash */ ''
          set -euo pipefail

          if [ "$#" -lt 1 ]; then
            echo "Usage: proton-tricks <winetricks-args...>" >&2
            echo "" >&2
            echo "Runs winetricks using Proton's Wine in the proton-run prefix." >&2
            echo "Respects PROTON_VERSION, PROTON_RUN_PREFIX, and STEAM_COMPAT_DATA_PATH." >&2
            echo "" >&2
            echo "Environment variables:" >&2
            echo "  PROTON_VERSION - Proton version to use (same as proton-run)" >&2
            echo "  PROTON_RUN_PREFIX - Custom prefix directory (default: ~/.local/share/proton-prefixes/<proton-name>)" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  proton-tricks vcrun2022                    # Install VC++ 2022 runtime" >&2
            echo "  proton-tricks vcrun2019 vcrun2022          # Install multiple runtimes" >&2
            echo "  PROTON_VERSION=Proton-Experimental proton-tricks dotnet48" >&2
            exit 1
          fi

          ${protonDetectScript}

          # Find Proton's wine binary
          if [ -x "$proton_dir/files/bin/wine" ]; then
            export WINE="$proton_dir/files/bin/wine"
            export WINESERVER="$proton_dir/files/bin/wineserver"
          elif [ -x "$proton_dir/dist/bin/wine" ]; then
            export WINE="$proton_dir/dist/bin/wine"
            export WINESERVER="$proton_dir/dist/bin/wineserver"
          else
            echo "Warning: Could not find Proton's wine binary, using system winetricks" >&2
          fi

          echo "Prefix: $WINEPREFIX" >&2
          echo "Running: winetricks $*" >&2

          exec ${steamRunExe} winetricks "$@"
        '';
      };

      protonRunScript = pkgs.writeShellApplication {
        name = "proton-run";
        runtimeInputs = [
          customSteamRun
          pkgs.coreutils
          pkgs.findutils
        ];
        text = /* bash */ ''
          set -euo pipefail

          if [ "$#" -lt 1 ]; then
            echo "Usage: proton-run <program> [args...]" >&2
            echo "" >&2
            echo "Environment variables:" >&2
            echo "  PROTON_VERSION - Proton version to use. Searches:" >&2
            echo "                   - compatibilitytools.d (GE-Proton, etc.)" >&2
            echo "                   - steamapps/common (Proton-Experimental, etc.)" >&2
            echo "                   - Absolute paths (/path/to/proton)" >&2
            echo "                   Note: 'Proton-X' auto-translates to 'Proton - X'" >&2
            echo "  PROTON_RUN_PREFIX - Custom prefix directory (default: ~/.local/share/proton-prefixes/<proton-name>)" >&2
            echo "  STEAM_COMPAT_DATA_PATH - Override compat data path" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  proton-run game.exe" >&2
            echo "  PROTON_VERSION=Proton-Experimental proton-run game.exe" >&2
            echo "  PROTON_VERSION=GE-Proton9-20 proton-run game.exe" >&2
            exit 1
          fi

          ${protonDetectScript}

          exec ${steamRunExe} "$proton_dir/proton" run "$@"
        '';
      };
    in
    {
      options.programs."wine-tools".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Wine tools bundle (wine-staging, winetricks, proton-ge-bin).";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.wineWowPackages.staging;
          description = "The Wine package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cfg.package
          pkgs.winetricks
          protonCompatTool
          protonRunScript
          protonTricksScript
        ];
      };
    };
in
{
  flake.nixosModules.apps."wine-tools" = WineToolsModule;
}
