/*
  Package: magnitude
  Description: Local inference engine for agents that tunes its kernels to the host hardware.
  Homepage: https://magnitude.dev
  Documentation: https://docs.magnitude.dev
  Repository: https://github.com/magnitudedev/magnitude

  Summary:
    * Downloads open models and serves them to agent harnesses such as Claude Code and Codex.
    * Compiles and tunes its inference kernels for the local CPU, CUDA, or Vulkan device.

  Options:
    app: Open the Magnitude desktop application.
    serve: Run Magnitude in the foreground.
    status: Show the Magnitude owner, service, and active-model status.
    hardware: Show hardware and memory available to local inference.
    catalog: Find, compare, and download local models.
    models: Inspect and control local models on this computer.
    connections: Connect Magnitude models to agent harnesses.

  Notes:
    * Package sourced from llm-agents.nix flake (github:Bad3r/llm-agents.nix).
    * The bundled desktop-host.node refuses `magnitude serve` and the desktop app until
      /var/lib/magnitude-desktop/installation.lock exists, root-owned and mode 0444, as the
      upstream deb's preinst creates it.
    * The `magnitude` user service runs `magnitude serve`. Opening Desktop ends it with a
      successful exit, so it stays stopped until `systemctl --user start magnitude`.
    * Magnitude binds a single listener address and serves its CLI on loopback, so mesh access
      listens on every interface and the firewall opens the port only on the mesh interface.
      Remote inference requests must carry the API key from secrets/magnitude.yaml.
    * `client.*` configures `claude-local` (modules/agents/claude-code) and the Codex `local`
      profile (modules/agents/codex). Avoid `magnitude connections`: it rewrites the
      Nix-managed Claude Code and Codex configs to proxy all cloud traffic through Magnitude.
*/
{ config, inputs, ... }:
let
  meshInterface = config.flake.lib.nixos._firewallMeshInterface;
  port = 10100;
in
{
  flake.nixosModules.apps.magnitude =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      secretsRoot,
      ...
    }:
    let
      cfg = config.programs.magnitude.extended;
      owner = metaOwner.username;
      apiKeySecretFile = secretsRoot + "/magnitude.yaml";
      apiKeyPath = "/run/secrets/magnitude/api-key";
      apiKeyAvailable =
        builtins.pathExists apiKeySecretFile
        && lib.attrByPath [ "security" "repoSecrets" "enable" ] true config;
      meshAccess = cfg.enable && apiKeyAvailable;

      # Magnitude reads `network` only at startup; Desktop Settings and custom endpoints
      # share config.json, so the other keys are kept.
      applyNetworkConfig = pkgs.writeShellApplication {
        name = "magnitude-apply-network-config";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          config_dir="$HOME/.magnitude"
          config="$config_dir/config.json"
          mkdir -p "$config_dir"
          tmp=$(mktemp "$config.nix-XXXXXX")
          trap 'rm -f -- "$tmp"' EXIT

          {
            if [ -s "$config" ]; then cat -- "$config"; else printf '{}\n'; fi
          } | jq --rawfile key ${apiKeyPath} \
            --arg host ${lib.escapeShellArg "${config.networking.hostName}.internal"} '
              .network = {
                enabled: true,
                bind: "0.0.0.0",
                apiKey: ($key | rtrimstr("\n")),
                requireApiKey: true,
                allowedHosts: [$host]
              }
            ' >"$tmp"
          mv -f -- "$tmp" "$config"
        '';
      };
    in
    {
      options.programs.magnitude.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Magnitude and serve its models to the mesh.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.magnitude;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.magnitude";
          description = "The Magnitude package to use.";
        };

        client = {
          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = if cfg.enable then "http://127.0.0.1:${toString port}" else null;
            defaultText = lib.literalExpression ''if enable then "http://127.0.0.1:${toString port}" else null'';
            example = "http://songbird.internal:${toString port}";
            description = "Magnitude origin for `claude-local` and the Codex `local` profile, or null to install neither.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = "gemma-4-12b-it-qat:gguf:q4";
            description = "Magnitude model ID that `claude-local` and the Codex `local` profile request.";
          };

          contextWindow = lib.mkOption {
            type = lib.types.ints.positive;
            default = 128000;
            description = ''
              Context size, in tokens, that the clients compact within. Codex and Claude
              Code assume a larger window for unknown model IDs; the default fits every
              model Magnitude lists with a context of 125K or more.
            '';
          };

          apiKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default =
              if apiKeyAvailable && (cfg.enable || cfg.client.endpoint != null) then apiKeyPath else null;
            defaultText = lib.literalExpression ''"${apiKeyPath}" when secrets/magnitude.yaml is available'';
            description = "File holding the API key that the clients send, or null to send none.";
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];

          systemd.tmpfiles.settings.magnitude = {
            "/var/lib/magnitude-desktop".d = {
              mode = "0755";
              user = "root";
              group = "root";
            };
            "/var/lib/magnitude-desktop/installation.lock".f = {
              mode = "0444";
              user = "root";
              group = "root";
            };
          };

          systemd.user.services.magnitude = {
            description = "Magnitude inference server";
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = owner;
            serviceConfig = {
              ExecStartPre = lib.mkIf meshAccess (lib.getExe applyNetworkConfig);
              ExecStart = "${lib.getExe' cfg.package "magnitude"} serve";
              Restart = "on-failure";
              RestartSec = 1;
              TimeoutStopSec = 30;
            };
          };

          networking.firewall.interfaces.${meshInterface}.allowedTCPPorts = lib.mkIf meshAccess [ port ];
        })

        (lib.mkIf ((cfg.enable || cfg.client.endpoint != null) && apiKeyAvailable) {
          sops.secrets."magnitude/api-key" = {
            sopsFile = apiKeySecretFile;
            key = "magnitude_api_key";
            path = apiKeyPath;
            inherit owner;
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && !apiKeyAvailable) {
          warnings = [
            "programs.magnitude.extended.enable is true but ${toString apiKeySecretFile} is missing or repo secrets are disabled; Magnitude serves loopback only."
          ];
        })

        (lib.mkIf (!cfg.enable && cfg.client.endpoint != null && cfg.client.apiKeyFile == null) {
          warnings = [
            "programs.magnitude.extended.client.endpoint is ${cfg.client.endpoint} but client.apiKeyFile is null, which is the default when ${toString apiKeySecretFile} is missing or repo secrets are disabled; a remote Magnitude answers requests without a key with 401."
          ];
        })
      ];
    };
}
