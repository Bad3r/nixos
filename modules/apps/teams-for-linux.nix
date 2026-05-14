/*
  Package: teams-for-linux
  Description: Unofficial Microsoft Teams client for Linux with native system integration.
  Homepage: https://github.com/IsmaelMartinez/teams-for-linux
  Documentation: https://github.com/IsmaelMartinez/teams-for-linux/wiki
  Repository: https://github.com/IsmaelMartinez/teams-for-linux

  Summary:
    * Unofficial Teams client providing native desktop notifications and system tray integration.
    * Supports screen sharing, video calls, and all core Teams functionality through web wrapper.

  Options:
    --disable-gpu: Disable GPU acceleration if experiencing graphical issues.
    --enable-wayland: Enable native Wayland support for better performance on Wayland compositors.
*/
_:
let
  TeamsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.teams-for-linux.extended;
      teamsIcon = ../stylix/icons/teams-for-linux.svg;
      teamsTrayIcon = ../stylix/icons/teams-for-linux-tray.svg;
      appIconSizes = [
        16
        24
        32
        48
        64
        96
        128
        256
        512
        1024
      ];
      trayIconSizes = [
        16
        96
      ];
      themedPackage = cfg.package.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          pkgs.asar
          pkgs.librsvg
        ];

        postInstall = (old.postInstall or "") + ''
          renderTeamsIcon() {
            local size="$1"
            local source="$2"
            local output="$3"

            mkdir -p "$(dirname "$output")"
            ${pkgs.librsvg}/bin/rsvg-convert \
              --page-width "$size" \
              --page-height "$size" \
              --width "$size" \
              --height "$size" \
              --keep-aspect-ratio \
              "$source" > "$output"
          }

          renderTeamsTrayIcon() {
            local size="$1"
            local source="$2"
            local output="$3"
            local glyphSize="$((size * 11 / 16))"
            local offset="$(((size - glyphSize) / 2))"

            mkdir -p "$(dirname "$output")"
            ${pkgs.librsvg}/bin/rsvg-convert \
              --page-width "$size" \
              --page-height "$size" \
              --width "$glyphSize" \
              --height "$glyphSize" \
              --left "$offset" \
              --top "$offset" \
              --keep-aspect-ratio \
              "$source" > "$output"
          }

          install -Dm444 ${teamsIcon} \
            "$out/share/icons/hicolor/scalable/apps/teams-for-linux.svg"

          for size in ${lib.escapeShellArgs (map toString appIconSizes)}; do
            renderTeamsIcon \
              "$size" \
              ${teamsIcon} \
              "$out/share/icons/hicolor/''${size}x''${size}/apps/teams-for-linux.png"
          done

          asarRoot="$(mktemp -d)"
          ${pkgs.asar}/bin/asar extract \
            "$out/share/teams-for-linux/app.asar" \
            "$asarRoot"

          for size in ${lib.escapeShellArgs (map toString trayIconSizes)}; do
            renderTeamsTrayIcon \
              "$size" \
              ${teamsTrayIcon} \
              "$asarRoot/app/assets/icons/icon-''${size}x''${size}.png"

            for variant in dark light; do
              renderTeamsTrayIcon \
                "$size" \
                ${teamsTrayIcon} \
                "$asarRoot/app/assets/icons/icon-monochrome-''${variant}-''${size}x''${size}.png"
            done
          done

          ${pkgs.asar}/bin/asar pack \
            "$asarRoot" \
            "$asarRoot/app.asar"
          cp "$asarRoot/app.asar" "$out/share/teams-for-linux/app.asar"
        '';
      });
    in
    {
      options.programs.teams-for-linux.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable teams-for-linux.";
        };

        package = lib.mkPackageOption pkgs "teams-for-linux" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ themedPackage ];
      };
    };
in
{
  flake.nixosModules.apps.teams-for-linux = TeamsModule;
}
