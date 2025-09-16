{
  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    let
      protonCompatTool = pkgs.proton-ge-bin.steamcompattool;
      steamRunExe = lib.getExe pkgs.steam-run;
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
    in
    {
      environment.systemPackages = with pkgs; [
        # Wine staging - the latest development version with experimental features
        wine-staging
        # Additional Wine tools
        winetricks
        # 32-bit support for Wine (with embedded Gecko/Mono installers)
        wineWowPackages.stagingFull
        # Proton-GE compatibility layer and helper wrapper
        protonCompatTool
        protonRunScript
      ];
    };
}
