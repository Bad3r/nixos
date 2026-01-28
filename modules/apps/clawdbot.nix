/*
  Package: clawdbot
  Description: Personal AI assistant with WhatsApp, Telegram, Discord integration.
  Homepage: https://clawd.bot
  Documentation: https://docs.molt.bot/getting-started
  Repository: https://github.com/clawdbot/clawdbot

  Summary:
    * Open-source personal AI assistant that runs locally with persistent memory and context across conversations.
    * Integrates with 50+ services including WhatsApp, Telegram, Discord, Slack, email, calendar, and browser automation.

  Options:
    onboard: Initial setup and onboarding command.
    --install-method git: Alternative installation via Git repository.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.clawdbot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.clawdbot.extended;
    in
    {
      options.programs.clawdbot.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable clawdbot.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.clawdbot;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.clawdbot";
          description = "The clawdbot package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
