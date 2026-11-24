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
    * Draws the tray icon as the Antigravity mark in the bar's status text color.
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
      trayIcon = config.lib.stylix.colors {
        template = builtins.readFile ../../stylix/icons/antigravity-tray.svg.mustache;
        extension = ".svg";
      };
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
              resources="$out/share/antigravity/resources"
              size=256
              glyphSize="$((size * 11 / 16))"
              offset="$(((size - glyphSize) / 2))"
              ${pkgs.librsvg}/bin/rsvg-convert \
                --page-width "$size" \
                --page-height "$size" \
                --width "$glyphSize" \
                --height "$glyphSize" \
                --left "$offset" \
                --top "$offset" \
                --keep-aspect-ratio \
                ${trayIcon} > "$resources/antigravity-tray.png"
              ${pkgs.python3.interpreter} -I ${./_tray-icon.py} \
                "$resources/app.asar" antigravity-tray.png
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
          description = "The antigravity-hub package with the configured language server flags, tray icon, and controlled agent shell.";
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
