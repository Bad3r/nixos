/*
  Package: chatgpt
  Description: Official desktop application for ChatGPT and Codex.
  Homepage: https://chatgpt.com/
  Documentation: https://learn.chatgpt.com/docs/app
  Repository: nil

  Summary:
    * Provides ChatGPT and Codex projects, local file access, and desktop workflows.

  Notes:
    * Shares agent state in `$CODEX_HOME` with the Codex CLI.
    * Draws the tray icon as the OpenAI mark in the bar's status text color.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.chatgpt =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.chatgpt.extended;
      # Tray glyph in the bar's status text color.
      trayIcon = config.lib.stylix.colors {
        template = builtins.replaceStrings [ "{{base05-hex}}" ] [ "{{base04-hex}}" ] (
          builtins.readFile ../../stylix/icons/openai-blossom.svg.mustache
        );
        extension = ".svg";
      };
      themedPackage = cfg.package.override {
        chatgpt-unwrapped = cfg.package.unwrapped.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            resources="$out/lib/chatgpt/resources"
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
              ${trayIcon} > "$resources/chatgpt-tray.png"
            ${pkgs.python3.interpreter} -I ${./_tray-icon.py} \
              "$resources/app.asar" chatgpt-tray.png
          '';
        });
      };
    in
    {
      options.programs.chatgpt.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the ChatGPT desktop application.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.chatgpt";
          description = "The ChatGPT desktop package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ themedPackage ];
      };
    };
}
