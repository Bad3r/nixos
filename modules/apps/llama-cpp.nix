/*
  Package: llama-cpp
  Description: Inference server for GGUF models, built with CUDA.
  Homepage: https://github.com/ggml-org/llama.cpp
  Documentation: https://github.com/ggml-org/llama.cpp/tree/master/tools/server
  Repository: https://github.com/ggml-org/llama.cpp

  Summary:
    * Runs `llama-server` as the nixpkgs `services.llama-cpp` system service, from this module's package.
    * Serves OpenAI Chat Completions and Responses, Anthropic Messages, and a built-in web UI.
    * `embeddings.enable` adds `llama-cpp-embed`, a CPU embeddings server.
    * `transcription.enable` adds `llama-cpp-transcribe`, which transcribes audio files over
      `/v1/audio/transcriptions`, and `dictation.enable` adds `llama-cpp-dictate`, which
      transcribes live English audio over the `/v1/realtime` WebSocket. Both run on the Intel
      iGPU through Vulkan, which `package` must support, and accept the main server's keys.
    * The three extra servers listen on loopback only.

  Notes:
    * The host sets `services.llama-cpp.settings`: listener, router flags, and models preset.
    * The service reads the API key from secrets/llama-cpp.yaml through a systemd credential.
      Without that secret, before the host's sopsRuntimeReady, or with security.repoSecrets
      disabled, it runs without a key, so the host binds a non-loopback listener only while
      `services.llama-cpp.apiKeyFile` is set.
    * `client.*` holds the endpoint, default model, context sizes, and API key that local clients use.
    * songbird builds the `llama-cpp` flake input, llama.cpp master, with CUDA for sm_120 only and
      Vulkan, so no cache serves its build. The host compiles it against CUDA libraries from
      cache.nixos-cuda.org.
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
      utils,
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
      consumerSecret = name: "llama-cpp/${name}-api-key";
      consumerSecrets = map consumerSecret (lib.attrNames cfg.apiKeys);
      # llama-server reads one key per line; the placeholders render without a trailing newline.
      keyFileContent =
        secrets: lib.concatMapStrings (name: config.sops.placeholder.${name} + "\n") secrets;
      routerKeysTemplate = "llama-cpp/router-api-keys";
      embedKeysTemplate = "llama-cpp/embed-api-keys";
      embedKeyed = apiKeyReady && cfg.apiKeys != { };
      embedCfg = cfg.embeddings;
      audioServers = {
        transcription = "llama-cpp-transcribe";
        dictation = "llama-cpp-dictate";
      };
      audioUnits = lib.mapAttrsToList (
        attr: unit: lib.optional cfg.${attr}.enable "${unit}.service"
      ) audioServers;
      enabledAudioUnits = lib.concatLists audioUnits;
      # The router's hardening, for a second llama-server that loads one model from the store.
      loopbackServerConfig =
        removeAttrs config.systemd.services.llama-cpp.serviceConfig [
          "ExecStart"
          "LoadCredential"
          "StateDirectory"
          "CacheDirectory"
          "WorkingDirectory"
          "Environment"
        ]
        // {
          IPAddressDeny = "any";
          IPAddressAllow = "localhost";
        };

      audioServerOptions =
        {
          unit,
          what,
          name,
          port,
          repo,
          rev,
          file,
          hash,
          mmprojHash,
          modelText,
        }:
        let
          fetch =
            f: h:
            pkgs.fetchurl {
              url = "https://huggingface.co/${repo}/resolve/${rev}/${f}";
              hash = h;
            };
        in
        {
          enable = lib.mkEnableOption "the `${unit}` ${what} server on loopback, on the Intel iGPU through Vulkan";

          model = lib.mkOption {
            type = lib.types.path;
            default = fetch file hash;
            defaultText = lib.literalMD "${modelText}, Q8_0, from `${repo}`";
            description = "Speech recognition model GGUF.";
          };

          mmproj = lib.mkOption {
            type = lib.types.path;
            default = fetch "mmproj-${file}" mmprojHash;
            defaultText = lib.literalMD "the Q8_0 audio projector from `${repo}`";
            description = "Audio projector GGUF matching `model`.";
          };

          name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Model name the instance reports and clients send.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = port;
            description = "Loopback port of the server.";
          };
        };

      audioServerConfig =
        attr: extraArgs:
        let
          srv = cfg.${attr};
          unit = audioServers.${attr};
        in
        lib.mkIf srv.enable {
          assertions = [
            {
              assertion = cfg.enable;
              message = "programs.llama-cpp.extended.${attr}.enable takes its unit hardening and API key from the llama-cpp service; set programs.llama-cpp.extended.enable too.";
            }
          ];

          systemd.services.${unit} = lib.mkIf cfg.enable {
            description = "llama.cpp ${attr} server";
            wantedBy = [ "multi-user.target" ];
            after = lib.optionals apiKeyReady (sopsInstallSecretsDeps config);
            requires = lib.optionals apiKeyReady (sopsInstallSecretsDeps config);
            environment = {
              # Leaves the Intel iGPU as the only device, so Vulkan0 cannot be a discrete GPU.
              CUDA_VISIBLE_DEVICES = "-1";
              VK_DRIVER_FILES = config.gpu.intel.vulkanDecode.intelIcd;
            };
            serviceConfig = loopbackServerConfig // {
              ExecStart =
                utils.escapeSystemdExecArgs (
                  [
                    (lib.getExe' cfg.package "llama-server")
                    "--model"
                    srv.model
                    "--mmproj"
                    srv.mmproj
                    "--alias"
                    srv.name
                    "--host"
                    "127.0.0.1"
                    "--port"
                    (toString srv.port)
                    "--device"
                    "Vulkan0"
                    "--n-gpu-layers"
                    "all"
                    "--no-webui"
                  ]
                  ++ extraArgs
                )
                + lib.optionalString apiKeyReady " --api-key-file %d/api-key";
              LoadCredential = lib.optional apiKeyReady "api-key:${config.services.llama-cpp.apiKeyFile}";
              # NVIDIA's CUDA and Vulkan drivers need /dev/nvidia*, which stays closed.
              DevicePolicy = "closed";
              DeviceAllow = [ "char-drm rw" ];
            };
          };
        };
    in
    {
      options.programs.llama-cpp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the llama.cpp server.";
        };

        package = lib.mkPackageOption pkgs "llama-cpp-cuda" { };

        apiKeys = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            paperless = "llama_cpp_paperless_api_key";
          };
          description = ''
            Keys of secrets/llama-cpp.yaml by consumer name. The server accepts each besides the
            client key, and the embeddings instance accepts only these. Each is declared as the
            root-owned `sops.secrets."llama-cpp/<name>-api-key"`, whose placeholder the consumer
            renders where it reads the key.
          '';
        };

        apiKeySecrets = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          default = lib.mapAttrs (name: _: consumerSecret name) cfg.apiKeys;
          defaultText = lib.literalExpression ''lib.mapAttrs (name: _: "llama-cpp/''${name}-api-key") apiKeys'';
          description = "Name of the `sops.secrets` entry holding each `apiKeys` consumer's key.";
        };

        embeddings = {
          enable = lib.mkEnableOption "the `llama-cpp-embed` embeddings server on loopback, CPU only";

          model = lib.mkOption {
            type = lib.types.path;
            default = pkgs.fetchurl {
              url = "https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/58faf90940886df2d62be555c8765d00dac362c5/embeddinggemma-2-Q8_0.gguf";
              hash = "sha256-IYisHeykt33/79YDwndqnXbZ107AGEE5KYLruECwkTU=";
            };
            defaultText = lib.literalMD "EmbeddingGemma 2, Q8_0, from `ggml-org/embeddinggemma-2-GGUF`";
            description = ''
              Embedding model GGUF. A different model produces incompatible vectors, so every
              index built from the old one needs a rebuild.
            '';
          };

          name = lib.mkOption {
            type = lib.types.str;
            default = "embeddinggemma-2";
            description = "Model name the instance reports and clients send.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 10101;
            description = "Loopback port of the embeddings server.";
          };

          threads = lib.mkOption {
            type = lib.types.ints.positive;
            default = 8;
            description = "CPU threads for embedding.";
          };
        };

        transcription = audioServerOptions {
          unit = audioServers.transcription;
          what = "audio file transcription";
          name = "qwen3-asr-1.7b";
          port = 10102;
          repo = "ggml-org/Qwen3-ASR-1.7B-GGUF";
          rev = "36a678687ba7d07a74ca70ccb0e36902e005fb80";
          file = "Qwen3-ASR-1.7B-Q8_0.gguf";
          hash = "sha256-WOItBTLU6srwNM+sF6b+0VnzfEE5DHEBhng75DnR/Fc=";
          mmprojHash = "sha256-RsHVM68/NUzrN86FXbzv99p/p88ealI987E0QL0WTA0=";
          modelText = "Qwen3-ASR 1.7B";
        };

        dictation = audioServerOptions {
          unit = audioServers.dictation;
          what = "live English transcription";
          name = "lfm3-audio-2b";
          port = 10103;
          repo = "LiquidAI/LFM3-Audio-2B-GGUF";
          rev = "642697a5597a675cb819ed236ac415c1e60a4f6f";
          file = "LFM3-Audio-2B-Q8_0.gguf";
          hash = "sha256-1ONpArqPDuezM1lgMKWdZQ+IrHZmC02bpf93w8Ilj8A=";
          mmprojHash = "sha256-JmAekEJFqFvY888yCmKeiXz8AcHQk2notP2VHxMCTT4=";
          modelText = "LFM3-Audio 2B";
        };

        client = {
          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default =
              if cfg.enable then "http://127.0.0.1:${toString config.services.llama-cpp.settings.port}" else null;
            defaultText = lib.literalExpression ''if enable then "http://127.0.0.1:''${toString config.services.llama-cpp.settings.port}" else null'';
            example = "http://songbird.internal:10100";
            description = "Server origin local clients use, or null for none.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            example = "gemma-4-26b-a4b";
            description = "Model name, a section of the server's models preset, that clients request by default.";
          };

          models = lib.mkOption {
            type = lib.types.attrsOf lib.types.ints.positive;
            default = {
              ${cfg.client.model} = 128000;
            };
            defaultText = lib.literalExpression "{ \${client.model} = 128000; }";
            example = {
              gemma-4-26b-a4b = 119808;
            };
            description = ''
              Context size, in tokens, per model of the server's models preset that
              clients may request, keyed by section name. Clients compact within it
              and otherwise guess the window from the model name; keep each within the
              server's context for the model.
            '';
          };

          apiKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = if apiKeyReady && keyNeeded then apiKeyPath else null;
            defaultText = lib.literalExpression ''"${apiKeyPath}" when secrets/llama-cpp.yaml is available'';
            description = "File holding the API key clients send, or null for a placeholder key.";
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          services.llama-cpp = {
            enable = true;
            inherit (cfg) package;
            apiKeyFile = lib.mkIf apiKeyReady (
              if cfg.apiKeys == { } then apiKeyPath else config.sops.templates.${routerKeysTemplate}.path
            );
          };

          systemd.services.llama-cpp = lib.mkIf apiKeyReady {
            after = sopsInstallSecretsDeps config;
            requires = sopsInstallSecretsDeps config;
          };
        })

        (lib.mkIf (cfg.enable && apiKeyReady && cfg.apiKeys != { }) {
          sops.secrets = lib.mapAttrs' (
            name: key:
            lib.nameValuePair (consumerSecret name) {
              sopsFile = apiKeySecretFile;
              inherit key;
              owner = "root";
              group = "root";
              mode = "0400";
            }
          ) cfg.apiKeys;

          # PID 1 reads both files for LoadCredential, so they stay root-only.
          sops.templates.${routerKeysTemplate} = {
            content = keyFileContent ([ "llama-cpp/api-key" ] ++ consumerSecrets);
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "llama-cpp.service" ] ++ enabledAudioUnits;
          };
        })

        (lib.mkIf (embedCfg.enable && embedKeyed) {
          sops.templates.${embedKeysTemplate} = {
            content = keyFileContent consumerSecrets;
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "llama-cpp-embed.service" ];
          };
        })

        (lib.mkIf embedCfg.enable {
          assertions = [
            {
              assertion = cfg.enable;
              message = "programs.llama-cpp.extended.embeddings.enable takes its unit hardening from the llama-cpp service; set programs.llama-cpp.extended.enable too.";
            }
          ];

          systemd.services.llama-cpp-embed = lib.mkIf cfg.enable {
            description = "llama.cpp embeddings server";
            wantedBy = [ "multi-user.target" ];
            after = lib.optionals embedKeyed (sopsInstallSecretsDeps config);
            requires = lib.optionals embedKeyed (sopsInstallSecretsDeps config);
            serviceConfig = loopbackServerConfig // {
              ExecStart =
                utils.escapeSystemdExecArgs [
                  (lib.getExe' cfg.package "llama-server")
                  "--model"
                  embedCfg.model
                  "--alias"
                  embedCfg.name
                  "--embeddings"
                  "--host"
                  "127.0.0.1"
                  "--port"
                  (toString embedCfg.port)
                  "--device"
                  "none"
                  "--threads"
                  (toString embedCfg.threads)
                  # Four slots of 2048 tokens; an input must fit one ubatch.
                  "--ctx-size"
                  "8192"
                  "--parallel"
                  "4"
                  "--batch-size"
                  "2048"
                  "--ubatch-size"
                  "2048"
                  "--no-webui"
                ]
                + lib.optionalString embedKeyed " --api-key-file %d/api-key";
              LoadCredential = lib.optional embedKeyed "api-key:${
                config.sops.templates.${embedKeysTemplate}.path
              }";
              PrivateDevices = true;
            };
          };
        })

        (audioServerConfig "transcription" [
          # The benchmarked size: a lone request fits about 34 minutes of audio at about 16 tokens per second.
          "--ctx-size"
          "32768"
          "--parallel"
          "4"
          "--kv-unified"
          # Frees the weights and KV cache in shared memory; the next request waits for the reload.
          "--sleep-idle-seconds"
          "1800"
        ])

        # No --sleep-idle-seconds: /v1/realtime reads the audio sample rate from the freed mtmd context
        # before it wakes the server.
        (audioServerConfig "dictation" [
          # The benchmarked size; a live session restarts its context every 15 to 30 seconds of speech.
          "--ctx-size"
          "32768"
          "--parallel"
          "4"
          "--kv-unified"
        ])

        (lib.mkIf (keyNeeded && apiKeyReady) {
          sops.secrets."llama-cpp/api-key" = {
            sopsFile = apiKeySecretFile;
            key = "llama_cpp_api_key";
            path = apiKeyPath;
            inherit owner;
            mode = "0400";
            restartUnits = lib.optional cfg.enable "llama-cpp.service" ++ enabledAudioUnits;
          };
        })

        (lib.mkIf (cfg.enable && !apiKeyReady) {
          warnings = [
            "programs.llama-cpp.extended.enable is true but ${toString apiKeySecretFile} is missing, flake.lib.nixos.hosts.${hostName}.sopsRuntimeReady is false, or security.repoSecrets.enable is false; llama-server runs without an API key."
          ];
        })

        (lib.mkIf (cfg.client.endpoint != null) {
          assertions = [
            {
              assertion = cfg.client.models ? ${cfg.client.model};
              message = "programs.llama-cpp.extended.client.models has no entry for client.model ${cfg.client.model}.";
            }
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
