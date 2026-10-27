/*
  Package: llama-cpp
  Description: Inference server for GGUF models, built with CUDA.
  Homepage: https://github.com/ggml-org/llama.cpp
  Documentation: https://github.com/ggml-org/llama.cpp/tree/master/tools/server
  Repository: https://github.com/ggml-org/llama.cpp

  Summary:
    * Runs `llama-server` as the nixpkgs `services.llama-cpp` system service, from this module's package.
    * Serves OpenAI Chat Completions and Responses, Anthropic Messages, and a built-in web UI.

  Notes:
    * The host sets `services.llama-cpp.settings`: listener, router flags, and models preset.
    * The service reads the API key from secrets/llama-cpp.yaml through a systemd credential.
      Without that secret, before the host's sopsRuntimeReady, or with security.repoSecrets
      disabled, it runs without a key, so the host binds a non-loopback listener only while
      `services.llama-cpp.apiKeyFile` is set.
    * `client.*` configures `claude-local` (modules/agents/claude-code) and the Codex `local`
      profile (modules/agents/codex).
    * The default package substitutes from cache.nixos-cuda.org; without that cache the host
      compiles CUDA llama.cpp.
*/
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
in
{
  nixpkgs.allowedUnfreePackages = [
    "cccl"
    "cuda_crt"
    "cuda_cudart"
    "cuda_nvcc"
    "cuda_nvrtc"
    "libcublas"
    "libnvvm"
  ];

  flake.nixosModules.apps.llama-cpp =
    {
      config,
      hostName,
      lib,
      metaOwner,
      pkgs,
      secretsRoot,
      ...
    }:
    let
      cfg = config.programs.llama-cpp.extended;
      owner = metaOwner.username;
      apiKeySecretFile = secretsRoot + "/llama-cpp.yaml";
      apiKeyPath = "/run/secrets/llama-cpp/api-key";
      # Both halves, as every other secret consumer gates: the file arriving
      # before the age identity would activate sops.secrets with no key to
      # decrypt and fail activation mid-switch.
      apiKeyReady =
        (hostsRegistry.${hostName}.sopsRuntimeReady or false)
        && lib.attrByPath [ "security" "repoSecrets" "enable" ] true config
        && builtins.pathExists apiKeySecretFile;
      keyNeeded = cfg.enable || cfg.client.endpoint != null;
    in
    {
      options.programs.llama-cpp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the llama.cpp server.";
        };

        package = lib.mkPackageOption pkgs "llama-cpp-cuda" { };

        client = {
          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default =
              if cfg.enable then "http://127.0.0.1:${toString config.services.llama-cpp.settings.port}" else null;
            defaultText = lib.literalExpression ''if enable then "http://127.0.0.1:''${toString config.services.llama-cpp.settings.port}" else null'';
            example = "http://songbird.internal:10100";
            description = "Server origin for `claude-local` and the Codex `local` profile, or null to install neither.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            example = "gemma-4-12b-it-qat";
            description = "Model name, a section of the server's models preset, that `claude-local` and the Codex `local` profile request.";
          };

          contextWindow = lib.mkOption {
            type = lib.types.ints.positive;
            default = 128000;
            description = ''
              Context size, in tokens, that the clients compact within. Codex and Claude
              Code assume a larger window for unknown model names; keep it within the
              server's context for the model.
            '';
          };

          apiKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = if apiKeyReady && keyNeeded then apiKeyPath else null;
            defaultText = lib.literalExpression ''"${apiKeyPath}" when secrets/llama-cpp.yaml is available'';
            description = "File holding the API key that the clients send, or null to send none.";
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          services.llama-cpp = {
            enable = true;
            inherit (cfg) package;
            apiKeyFile = lib.mkIf apiKeyReady apiKeyPath;
          };

          systemd.services.llama-cpp = lib.mkIf apiKeyReady {
            after = sopsInstallSecretsDeps config;
            requires = sopsInstallSecretsDeps config;
          };
        })

        (lib.mkIf (keyNeeded && apiKeyReady) {
          sops.secrets."llama-cpp/api-key" = {
            sopsFile = apiKeySecretFile;
            key = "llama_cpp_api_key";
            path = apiKeyPath;
            inherit owner;
            mode = "0400";
            restartUnits = lib.optional cfg.enable "llama-cpp.service";
          };
        })

        (lib.mkIf (cfg.enable && !apiKeyReady) {
          warnings = [
            "programs.llama-cpp.extended.enable is true but ${toString apiKeySecretFile} is missing, flake.lib.nixos.hosts.${hostName}.sopsRuntimeReady is false, or security.repoSecrets.enable is false; llama-server runs without an API key."
          ];
        })

        (lib.mkIf (!cfg.enable && cfg.client.endpoint != null && cfg.client.apiKeyFile == null) {
          warnings = [
            "programs.llama-cpp.extended.client.endpoint is ${cfg.client.endpoint} but client.apiKeyFile is null, which is the default when ${toString apiKeySecretFile} is missing, sops is not ready on ${hostName}, or repo secrets are disabled; a remote llama-server answers requests without a key with 401."
          ];
        })
      ];
    };
}
