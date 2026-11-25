/*
  Package: antigravity-hub
  Description: Desktop environment for managing multiple autonomous agents across independent projects.
  Homepage: https://antigravity.google/
  Documentation: https://antigravity.google/docs
  Repository: nil

  Summary:
    * Provides the `antigravity` desktop app for running Google Antigravity agents across separate projects.
    * Ships the Electron app from the llm-agents.nix package, patched for NixOS.
    * Serves the Hub on a fixed port that Mesh peers reach through the firewall, with Language Server telemetry disabled.

  Notes:
    * Draws the window and tray icons as the Antigravity mark in Stylix colors, the tray in the bar's status text color.
    * Theme seeds and typeface come from Stylix through the Home Manager module (modules/agents/antigravity-cli/home.nix).
*/
{ config, inputs, ... }:
let
  meshInterface = config.flake.lib.nixos._firewallMeshInterface;
  inherit (config.flake.lib.agents) scratchDir;
  telemetry = import ../../agents/antigravity-cli/_telemetry.nix;

  AntigravityHubModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."antigravity-hub".extended;
      shell = import ../../agents/antigravity-cli/_shell.nix {
        inherit lib pkgs scratchDir;
      };
      sharedEnvArgs = lib.concatStringsSep " " (
        lib.mapAttrsToList (
          name: value: "--set ${lib.escapeShellArg name} ${lib.escapeShellArg value}"
        ) telemetry.sharedEnv
      );
      iconTemplate = builtins.readFile ../../stylix/icons/antigravity.svg.mustache;
      appIcon = config.lib.stylix.colors {
        template = iconTemplate;
        extension = ".svg";
      };
      # Tray glyph in the bar's status text color.
      trayIcon = config.lib.stylix.colors {
        template = builtins.replaceStrings [ "{{base05-hex}}" ] [ "{{base04-hex}}" ] iconTemplate;
        extension = ".svg";
      };
      iconSizes = [
        32
        64
        256
        512
      ];
      basePkg =
        (cfg.package.override {
          # The language server binds either localhost or 0.0.0.0; the firewall
          # limits the wildcard to loopback and Mesh.
          languageServerFlags = [
            "--https_server_port=${toString cfg.port}"
            "--remote_accessible"
          ]
          ++ telemetry.languageServerFlags;
        }).overrideAttrs
          (old: {
            postInstall = (old.postInstall or "") + ''
              renderAntigravityIcon() {
                local source="$1"
                local size="$2"
                local output="$3"
                local glyphSize="$((size * 11 / 16))"
                local offset="$(((size - glyphSize) / 2))"

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

              for size in ${lib.escapeShellArgs (map toString iconSizes)}; do
                iconDir="$out/share/icons/hicolor/''${size}x''${size}/apps"
                mkdir -p "$iconDir"
                renderAntigravityIcon ${appIcon} "$size" "$iconDir/antigravity.png"
              done

              resources="$out/share/antigravity/resources"
              asarRoot="$(mktemp -d)"
              ${pkgs.asar}/bin/asar extract "$resources/app.asar" "$asarRoot/app"

              # Window, taskbar, and IDE install wizard icon.
              renderAntigravityIcon ${appIcon} 512 "$asarRoot/app/icon.png"
              # The tray reads its own file instead of the window icon.
              renderAntigravityIcon ${trayIcon} 256 "$asarRoot/app/tray.png"
              substituteInPlace "$asarRoot/app/dist/tray.js" \
                --replace-fail \
                  "const iconFile = (0, utils_1.isMacOS)() ? 'trayTemplate.png' : 'icon.png';" \
                  "const iconFile = (0, utils_1.isMacOS)() ? 'trayTemplate.png' : 'tray.png';"

              ${pkgs.asar}/bin/asar pack \
                --unpack-dir node_modules/chrome-devtools-mcp \
                "$asarRoot/app" \
                "$asarRoot/app.asar"
              # A changed unpacked set would leave the header pointing at missing files.
              diff \
                <(cd "$resources/app.asar.unpacked" && find . | sort) \
                <(cd "$asarRoot/app.asar.unpacked" && find . | sort)
              cp "$asarRoot/app.asar" "$resources/app.asar"
            '';
          });
    in
    {
      options.programs."antigravity-hub".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity-hub.";
        };

        finalPackage = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "The antigravity-hub package with the configured language server flags, Stylix icons, and controlled agent shell.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-hub;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.antigravity-hub";
          description = "The antigravity-hub package to use.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 7777;
          description = "HTTPS port the Hub's language server serves local and Mesh clients on.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs."antigravity-hub".extended.finalPackage = pkgs.symlinkJoin (
          {
            name = "antigravity-hub-${basePkg.version or "custom"}";
            paths = [ basePkg ];
            passthru.basePackage = basePkg;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram "$out/bin/antigravity" \
                --prefix PATH : "${shell.antigravityBashWrapper}/bin:${shell.rmShim}/bin" \
                ${sharedEnvArgs} \
                --run ${lib.escapeShellArg ''
                  if [ -z "''${TMPDIR:-}" ] && [ -d ${lib.escapeShellArg scratchDir} ] && [ -w ${lib.escapeShellArg scratchDir} ]; then
                    export TMPDIR=${lib.escapeShellArg scratchDir}
                  fi
                ''}
            '';
          }
          // lib.optionalAttrs (basePkg ? version) { inherit (basePkg) version; }
          // lib.optionalAttrs (basePkg ? meta) { inherit (basePkg) meta; }
        );

        environment.systemPackages = [ cfg.finalPackage ];

        # The CSRF token and the window's bootstrap token gate every request.
        networking.firewall.interfaces.${meshInterface}.allowedTCPPorts = [ cfg.port ];
      };
    };
in
{
  flake.nixosModules.apps."antigravity-hub" = AntigravityHubModule;
}
