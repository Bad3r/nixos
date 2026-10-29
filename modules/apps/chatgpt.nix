/*
  Package: chatgpt
  Description: Official desktop application for ChatGPT and Codex.
  Homepage: https://chatgpt.com/
  Documentation: https://learn.chatgpt.com/docs/app
  Repository: nil

  Summary:
    * Provides ChatGPT and Codex projects, local file access, and desktop workflows.
    * Installs OpenAI's native Linux application with the input's NixOS runtime integration.

  Options:
    chatgpt: Launch the desktop application.

  Notes:
    * Package sourced from llm-agents.nix flake (github:Bad3r/llm-agents.nix).
    * Electron app with productName "Codex": its Chromium profile lives in
      $XDG_CONFIG_HOME/Codex, while its agent state shares $CODEX_HOME
      (~/.config/codex) with the CLI.
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
        environment.systemPackages = [ cfg.package ];
      };
    };
}
