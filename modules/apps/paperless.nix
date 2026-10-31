/*
  Package: paperless
  Description: Document management system that scans, indexes, and archives documents.
  Homepage: https://docs.paperless-ngx.com/
  Documentation: https://docs.paperless-ngx.com/configuration/
  Repository: https://github.com/paperless-ngx/paperless-ngx

  Notes:
    * AI features use the local llama.cpp server.
    * Exports every document nightly.
    * AI keys typed into the admin UI land in the export; keep keys in sops.
*/
_:
let
  PaperlessModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.paperless.extended;
      paperless = config.services.paperless;
      llama = config.programs.llama-cpp.extended;
      keySecret = llama.apiKeySecrets.paperless;
      keyed = config.sops.secrets ? ${keySecret};
      envTemplate = "paperless/ai.env";
      loopback = port: "http://127.0.0.1:${toString port}/v1";
      loopbackOnly = {
        IPAddressDeny = [ "any" ];
        IPAddressAllow = [ "localhost" ];
      };
      dataPaths = [
        paperless.mediaDir
        paperless.consumptionDir
      ];
    in
    {
      options.services.paperless.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable paperless-ngx with local AI.";
        };

        package = lib.mkPackageOption pkgs "paperless-ngx" { };
      };

      config = lib.mkIf cfg.enable {
        programs.llama-cpp.extended = {
          enable = lib.mkOverride 1050 true;
          embeddings.enable = true;
          apiKeys.paperless = "llama_cpp_paperless_api_key";
        };

        services.paperless = {
          enable = true;
          inherit (cfg) package;
          database.createLocally = true;
          configureTika = true;
          environmentFile = lib.mkIf keyed config.sops.templates.${envTemplate}.path;
          exporter.enable = true;
          settings = {
            PAPERLESS_AI_ENABLED = true;
            PAPERLESS_AI_LLM_BACKEND = "openai-like";
            PAPERLESS_AI_LLM_ENDPOINT = loopback config.services.llama-cpp.settings.port;
            # The clients' model, so paperless never makes the router swap away from it.
            PAPERLESS_AI_LLM_MODEL = llama.client.model;
            PAPERLESS_AI_LLM_CONTEXT_SIZE = 16384;
            # Covers a model swap plus a wait behind an interactive client in the router's one slot.
            PAPERLESS_AI_LLM_REQUEST_TIMEOUT = 300;
            # The OpenAI SDK rejects non-standard top-level arguments; extra_body merges into the request JSON.
            PAPERLESS_AI_LLM_EXTRA_PARAMS = builtins.toJSON {
              extra_body.chat_template_kwargs.enable_thinking = false;
            };
            PAPERLESS_AI_LLM_EMBEDDING_BACKEND = "openai-like";
            PAPERLESS_AI_LLM_EMBEDDING_ENDPOINT = loopback llama.embeddings.port;
            PAPERLESS_AI_LLM_EMBEDDING_MODEL = llama.embeddings.name;
          };
        };

        # Owned by paperless rather than root: the exporter runs paperless-manage as paperless,
        # and the units already hold the key in their environment.
        sops.templates.${envTemplate} = lib.mkIf keyed {
          content = ''
            PAPERLESS_AI_LLM_API_KEY=${config.sops.placeholder.${keySecret}}
            PAPERLESS_AI_LLM_EMBEDDING_API_KEY=${config.sops.placeholder.${keySecret}}
          '';
          inherit (paperless) group;
          owner = paperless.user;
          mode = "0400";
          restartUnits = [
            "paperless-consumer.service"
            "paperless-scheduler.service"
            "paperless-task-queue.service"
            "paperless-web.service"
          ];
        };

        systemd.services = {
          # Only loopback: the AI endpoints, Tika, and Gotenberg. Mail fetch would need its server here.
          paperless-task-queue = {
            unitConfig.RequiresMountsFor = dataPaths;
            serviceConfig = loopbackOnly;
          };
          # The filter also checks the source of inbound connections, so a host serving the
          # web UI beyond loopback adds its client ranges to IPAddressAllow.
          paperless-web = {
            unitConfig.RequiresMountsFor = dataPaths;
            serviceConfig = loopbackOnly;
          };
          paperless-consumer.unitConfig.RequiresMountsFor = dataPaths;
          # They parse untrusted documents and only answer paperless on loopback.
          tika.serviceConfig = loopbackOnly;
          gotenberg.serviceConfig = loopbackOnly;
          paperless-exporter.unitConfig.RequiresMountsFor = dataPaths;
        };
      };
    };
in
{
  flake.nixosModules.apps.paperless = PaperlessModule;
}
