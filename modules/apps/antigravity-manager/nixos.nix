/*
  Package: antigravity-manager
  Description: Antigravity account manager and local Anthropic, OpenAI, and Gemini API proxy.
  Homepage: https://github.com/lbjlaq/Antigravity-Manager
  Documentation: https://github.com/lbjlaq/Antigravity-Manager#readme
  Repository: https://github.com/lbjlaq/Antigravity-Manager

  Summary:
    * Pools Google Antigravity accounts behind Anthropic Messages, OpenAI Responses and Chat Completions, and Gemini endpoints.
    * `antigravity-server switch` moves `agy` to another pooled account through the Secret Service and ~/.gemini.
    * Serves its management web UI on the proxy port; this module reaches it at http://antigravity-manager.internal.

  Notes:
    * Built from source in packages/antigravity-manager; CC BY-NC-SA 4.0 makes it unfree.
    * The Home Manager module runs `antigravity-server` as a user service and adds the `claude-antigravity` launcher and the `antigravity` Codex profile.
    * `antigravity-tools` without arguments opens the Tauri GUI, which starts its own proxy on the same port and data directory; stop the user service first.
*/
_:
let
  AntigravityManagerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services."antigravity-manager".extended;
    in
    {
      options.services."antigravity-manager".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity-manager.";
        };

        package = lib.mkPackageOption pkgs "antigravity-manager" { };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8045;
          description = "Port the proxy and web UI listen on at 127.0.0.1.";
        };

        hostname = lib.mkOption {
          type = lib.types.str;
          default = "antigravity-manager.internal";
          description = "Name that resolves to the loopback web UI.";
        };

        codexModel = lib.mkOption {
          type = lib.types.str;
          default = "claude-opus-5-5";
          description = "Model the `antigravity` Codex profile requests from the proxy.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        networking.loopbackSites.${cfg.hostname}.upstream = "http://127.0.0.1:${toString cfg.port}";
      };
    };
in
{
  flake.nixosModules.apps."antigravity-manager" = AntigravityManagerModule;
}
