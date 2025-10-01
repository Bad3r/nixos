_:
let
  defaultIccSource = ./profiles/leny27q-20.icm;
  defaultProfileFileName = "leny27q-20.icm";
  defaultVendor = "LEN";
  defaultModel = "Lenovo Y27q-20";
  defaultFallbackIds = [
    "xrandr-Lenovo Y27q-20"
    "xrandr-Lenovo_Y27q-20"
  ];

  monitorModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.hardware.monitors.lenovo-y27q-20;
      colordDir = "/var/lib/colord/icc";
      profilePath = "${colordDir}/${cfg.profileFileName}";
      sanitize = s: lib.replaceStrings [ " " ] [ "_" ] s;
      candidateIds = lib.unique (
        cfg.fallbackDeviceIds
        ++ [
          "xrandr-${sanitize cfg.match.model}"
          "xrandr-${cfg.match.model}"
          "xrandr-${cfg.match.vendor}-${sanitize cfg.match.model}"
        ]
      );
      assignScript = pkgs.writeShellScript "lenovo-y27q-20-colord-assign" ''
        set -euo pipefail

        COLORMGR=${pkgs.colord}/bin/colormgr
        PROFILE_PATH=${lib.escapeShellArg profilePath}
        MATCH_VENDOR=${lib.escapeShellArg (lib.toLower cfg.match.vendor)}
        MATCH_MODEL=${lib.escapeShellArg (lib.toLower cfg.match.model)}
        MATCH_SERIAL=${
          lib.escapeShellArg (lib.toLower (if cfg.match.serial == null then "" else cfg.match.serial))
        }

        trim() {
          printf '%s' "$1" | tr -d '\r'
        }

        device_path=""

        # Prefer EDID-based match so connectors (HDMI, DP, USB-C) do not matter
        while IFS= read -r dev; do
          [ -z "$dev" ] && continue
          info="$($COLORMGR get-device "$dev" 2>/dev/null || true)"
          vendor=$(trim "$(printf '%s\n' "$info" | sed -n 's/^\s*Vendor:\s*//p' | head -n1)")
          model=$(trim "$(printf '%s\n' "$info" | sed -n 's/^\s*Model:\s*//p' | head -n1)")
          serial=$(trim "$(printf '%s\n' "$info" | sed -n 's/^\s*Serial:\s*//p' | head -n1)")

          vendor_l=$(printf '%s' "$vendor" | tr '[:upper:]' '[:lower:]')
          model_l=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')
          serial_l=$(printf '%s' "$serial" | tr '[:upper:]' '[:lower:]')

          if [ -n "$MATCH_VENDOR" ] && [ "$vendor_l" != "$MATCH_VENDOR" ]; then
            continue
          fi
          if [ -n "$MATCH_MODEL" ] && [ "$model_l" != "$MATCH_MODEL" ]; then
            continue
          fi
          if [ -n "$MATCH_SERIAL" ] && [ "$serial_l" != "$MATCH_SERIAL" ]; then
            continue
          fi

          device_path="$dev"
          break
        done < <($COLORMGR get-devices-by-kind display 2>/dev/null || true)

        if [ -z "$device_path" ]; then
          for candidate in ${lib.concatStringsSep " " (map lib.escapeShellArg candidateIds)}; do
            if path="$($COLORMGR find-device "$candidate" 2>/dev/null)"; then
              device_path="$path"
              break
            fi
          done
        fi

        if [ -z "$device_path" ]; then
          echo "lenovo-y27q-20: no matching colord display device found" >&2
          exit 0
        fi

        profile_id="$($COLORMGR find-profile-by-filename "$PROFILE_PATH" 2>/dev/null || true)"
        if [ -z "$profile_id" ]; then
          $COLORMGR import-profile "$PROFILE_PATH" >/dev/null 2>&1 || true
          profile_id="$($COLORMGR find-profile-by-filename "$PROFILE_PATH" 2>/dev/null || true)"
        fi

        if [ -z "$profile_id" ]; then
          echo "lenovo-y27q-20: failed to register profile $PROFILE_PATH" >&2
          exit 1
        fi

        if ! $COLORMGR device-get-default-profile "$device_path" | grep -F "$profile_id" >/dev/null 2>&1; then
          $COLORMGR device-add-profile "$device_path" "$profile_id" >/dev/null 2>&1 || true
          $COLORMGR device-make-profile-default "$device_path" "$profile_id" >/dev/null 2>&1 || true
        fi
      '';
    in
    {
      options.hardware.monitors.lenovo-y27q-20 = {
        enable = lib.mkEnableOption "Install and assign the Lenovo Y27q-20 ICC profile";

        iccSource = lib.mkOption {
          type = lib.types.path;
          default = defaultIccSource;
          example = ./profiles/leny27q-20.icm;
          description = ''
            Path to the ICC/ICM color profile to install. The file is copied into the
            Nix store at build time for reproducibility.
          '';
        };

        profileFileName = lib.mkOption {
          type = lib.types.str;
          default = defaultProfileFileName;
          description = "Filename used under /var/lib/colord/icc for the profile.";
        };

        match = {
          vendor = lib.mkOption {
            type = lib.types.str;
            default = defaultVendor;
            description = "Vendor string reported by colord (case-insensitive).";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = defaultModel;
            description = "Model string reported by colord (case-insensitive).";
          };

          serial = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional serial/EDID identifier to disambiguate multiple units.";
          };
        };

        fallbackDeviceIds = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = defaultFallbackIds;
          description = ''
            Candidate colord device identifiers to try when vendor/model matching fails.
            Use values from `colormgr get-devices-by-kind display` or connector-based
            names such as `xrandr-HDMI-0`.
          '';
        };

        unitTriggers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "graphical.target" ];
          example = [
            "graphical-session.target"
            "multi-user.target"
          ];
          description = "Systemd targets that should start the assignment service.";
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.colord.enable = true;

            systemd.tmpfiles.rules = lib.mkAfter [
              "d ${colordDir} 0755 colord colord -"
              "L ${profilePath} - - - - ${cfg.iccSource}"
            ];

            systemd.services.lenovo-y27q-20-color-profile = {
              description = "Assign Lenovo Y27q-20 ICC profile";
              after = [
                "colord.service"
                "display-manager.service"
              ];
              wants = [ "colord.service" ];
              wantedBy = cfg.unitTriggers;
              serviceConfig = {
                Type = "oneshot";
                ExecStart = assignScript;
              };
            };
          }
        ]
      );
    };
in
{
  flake.nixosModules.hardware.monitors.lenovo-y27q-20 = monitorModule;
  flake.nixosModules."hardware-lenovo-y27q-20" = monitorModule;
}
