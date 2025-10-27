{ inputs, ... }:
let
  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        concatStringsSep
        literalExpression
        mapAttrs
        mapAttrs'
        mapAttrsToList
        mkEnableOption
        mkIf
        mkOption
        mkPackageOption
        optionalAttrs
        types
        genAttrs
        ;

      cfg = config.services.duplicati-r2;

      credentialsSecretPath = inputs.secrets + "/duplicati-r2.yaml";
      credentialsExist = builtins.pathExists credentialsSecretPath;

      credentialNames = [
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "R2_ACCOUNT_ID"
        "R2_API_TOKEN"
        "R2_BUCKET"
        "R2_S3_ENDPOINT"
        "R2_S3_ENDPOINT_URL"
        "R2_REGION"
        "DUPLICATI_PASSPHRASE"
      ];

      defaultCredentials = genAttrs credentialNames (name: {
        secret = "duplicati-r2/${name}";
      });

      credentialModule = types.submodule (
        { name, ... }:
        {
          options = {
            secret = mkOption {
              type = types.str;
              default = defaultCredentials.${name}.secret or "duplicati-r2/${name}";
              description = "SOPS selector that resolves to ${name}.";
            };
          };
        }
      );

      targetModule = types.submodule (
        { name, ... }:
        {
          options = {
            source = mkOption {
              type = types.path;
              description = "Absolute path that Duplicati should back up for target ${name}.";
              example = "/var/lib/data";
            };

            onCalendar = mkOption {
              type = types.str;
              description = "systemd OnCalendar expression scheduling backups for target ${name}.";
              example = "Tue,Fri 03:00:00";
            };

            stateDir = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Optional override for the per-target SQLite directory.";
              example = "/var/lib/duplicati-r2/home";
            };

            retention = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Duplicati retention rule applied to target ${name}.";
              example = "14D:1D,12M:1M";
            };

            extraArgs = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional arguments appended to duplicati-cli invocations for target ${name}.";
            };

            destSubpath = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional override for the destination subpath within the bucket. Defaults to the target key.";
            };
          };
        }
      );

      verifyModule = types.submodule {
        options = {
          onCalendar = mkOption {
            type = types.str;
            description = "systemd OnCalendar expression shared by verification timers.";
            example = "weekly";
          };

          samples = mkOption {
            type = types.ints.positive;
            default = 200;
            description = "Number of random samples duplicati-cli test should request.";
          };
        };
      };

      manifestDest = "/run/duplicati-r2/config.json";
      manifestTemplateName = "duplicati-r2-manifest.json";
      generatorServiceName = "duplicati-r2-generate-units";

      usingSecret = cfg.configFile != null;

      defaultStateDir = toString cfg.stateDir;
      defaultBucket = cfg.bucket;
      defaultEnvFile = toString cfg.environmentFile;
      effectiveHostname =
        if cfg.hostname != null && cfg.hostname != "" then
          cfg.hostname
        else
          config.networking.hostName or null;

      inlineManifest =
        if usingSecret then
          null
        else
          {
            environmentFile = defaultEnvFile;
            bucket = defaultBucket;
            stateDir = defaultStateDir;
          }
          // optionalAttrs (effectiveHostname != null) { hostname = effectiveHostname; }
          // {
            targets = mapAttrs (name: target: {
              path = toString target.source;
              inherit (target)
                onCalendar
                retention
                extraArgs
                destSubpath
                ;
              stateDir =
                if target.stateDir != null then toString target.stateDir else "${defaultStateDir}/${name}";
            }) cfg.targets;
          }
          // optionalAttrs (cfg.verify != null) {
            verify = {
              inherit (cfg.verify) onCalendar samples;
            };
          };

      manifestSource =
        if usingSecret then
          manifestDest
        else
          pkgs.writeText "duplicati-r2-manifest.json" (builtins.toJSON inlineManifest);

      backupScript = pkgs.writeShellApplication {
        name = "duplicati-r2-backup";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.hostname
          pkgs.jq
        ];
        text = ''
          set -euo pipefail

          config_path="''${DUPLICATI_R2_CONFIG:?DUPLICATI_R2_CONFIG not set}"
          slug="''${DUPLICATI_R2_TARGET:?DUPLICATI_R2_TARGET not set}"

          if [ ! -s "$config_path" ]; then
            echo "Duplicati R2: config $config_path not found or empty" >&2
            exit 1
          fi

          target_json=$(jq --arg slug "$slug" -c '.targets[$slug] // empty' "$config_path")
          if [ -z "$target_json" ] || [ "$target_json" = "null" ]; then
            echo "Duplicati R2: unknown target $slug" >&2
            exit 1
          fi

          path=$(jq -r '.path // empty' <<<"$target_json")
          if [ -z "$path" ]; then
            echo "Duplicati R2: target $slug missing path" >&2
            exit 1
          fi

          dest_subpath=$(jq -r '.destSubpath // empty' <<<"$target_json")
          if [ -z "$dest_subpath" ]; then
            dest_subpath="$slug"
          fi

          retention=$(jq -r '.retention // empty' <<<"$target_json")

          mapfile -t extra_args < <(jq -r '.extraArgs // [] | .[]' <<<"$target_json")

          state_dir=$(jq -r '.stateDir // empty' <<<"$target_json")
          if [ -z "$state_dir" ]; then
            state_dir=$(jq -r '.stateDir // empty' "$config_path")
          fi
          if [ -z "$state_dir" ] || [ "$state_dir" = "null" ]; then
            state_dir="''${DUPLICATI_R2_DEFAULT_STATE_DIR:-/var/lib/duplicati-r2}"
          fi

          env_file=$(jq -r '.environmentFile // empty' "$config_path")
          if [ -z "$env_file" ] || [ "$env_file" = "null" ]; then
            env_file="''${DUPLICATI_R2_DEFAULT_ENV_FILE:-/etc/duplicati/r2.env}"
          fi
          if [ ! -f "$env_file" ]; then
            echo "Duplicati R2: missing environment file $env_file" >&2
            exit 1
          fi

          bucket=$(jq -r '.bucket // empty' "$config_path")
          if [ -z "$bucket" ] || [ "$bucket" = "null" ]; then
            bucket="''${DUPLICATI_R2_DEFAULT_BUCKET:-duplicati-nixos-backups}"
          fi

          manifest_hostname=$(jq -r '.hostname // empty' "$config_path")
          if [ -n "$manifest_hostname" ] && [ "$manifest_hostname" != "null" ]; then
            hostname="$manifest_hostname"
          elif [ -n "''${DEFAULT_HOSTNAME:-}" ]; then
            hostname="''${DEFAULT_HOSTNAME}"
          else
            hostname=$(hostname --short 2>/dev/null || hostname 2>/dev/null || echo duplicati)
          fi

          mkdir -p "$state_dir"

          db_slug=$(jq -nr --arg s "$slug" '$s | gsub("[^A-Za-z0-9_\\-]"; "-")')
          db_path="$state_dir/duplicati-r2-$db_slug.sqlite"

          # shellcheck disable=SC1090
          . "$env_file"

          if [ -z "''${AWS_ACCESS_KEY_ID:-}" ] || [ -z "''${AWS_SECRET_ACCESS_KEY:-}" ]; then
            echo "Duplicati R2: AWS credentials missing" >&2
            exit 1
          fi

          endpoint_host="''${R2_S3_ENDPOINT:-}"
          if [ -z "$endpoint_host" ] && [ -n "''${R2_ACCOUNT_ID:-}" ]; then
            endpoint_host="''${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
          fi

          if [ -n "''${R2_S3_ENDPOINT_URL:-}" ]; then
            export AWS_ENDPOINT_URL="''${R2_S3_ENDPOINT_URL}"
          elif [ -n "$endpoint_host" ]; then
            export AWS_ENDPOINT_URL="https://$endpoint_host"
          fi

          export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
          export AUTH_USERNAME="$AWS_ACCESS_KEY_ID"
          export AUTH_PASSWORD="$AWS_SECRET_ACCESS_KEY"

          if [ -z "''${AWS_REGION:-}" ] && [ -z "''${AWS_DEFAULT_REGION:-}" ]; then
            if [ -n "''${R2_REGION:-}" ]; then
              export AWS_REGION="''${R2_REGION}"
              export AWS_DEFAULT_REGION="''${R2_REGION}"
            else
              export AWS_REGION=auto
              export AWS_DEFAULT_REGION=auto
            fi
          fi

          encoded_subpath=$(jq -nr --arg s "$dest_subpath" '$s | @uri')

          region_suffix=""
          if [ -n "''${R2_REGION:-}" ]; then
            region_suffix="&s3-ext-region=$R2_REGION"
          fi

          server_param=""
          if [ -n "$endpoint_host" ]; then
            server_param="&s3-server-name=$endpoint_host"
          fi

          dest="s3://$bucket/$hostname/$encoded_subpath?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio''${server_param}''${region_suffix}"

          if [ -z "''${DUPLICATI_PASSPHRASE:-}" ]; then
            echo "Duplicati R2: DUPLICATI_PASSPHRASE missing from environment" >&2
            exit 1
          fi
          export PASSPHRASE="''${DUPLICATI_PASSPHRASE}"

          args=(
            backup "$dest" "$path"
            --backup-name="duplicati-r2-$db_slug"
            --dbpath="$db_path"
            --full-result
          )

          if [ -n "$retention" ]; then
            if [[ "$retention" == *:* ]]; then
              args+=("--retention-policy=$retention")
            else
              args+=("--keep-time=$retention")
            fi
          fi

          for arg in "''${extra_args[@]}"; do
            args+=("$arg")
          done

          set -- "''${args[@]}"
          exec ${cfg.package}/bin/duplicati-cli "$@"
        '';
      };

      verifyScript = pkgs.writeShellApplication {
        name = "duplicati-r2-verify";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.hostname
          pkgs.jq
        ];
        text = ''
          set -euo pipefail

          config_path="''${DUPLICATI_R2_CONFIG:?DUPLICATI_R2_CONFIG not set}"
          slug="''${DUPLICATI_R2_TARGET:?DUPLICATI_R2_TARGET not set}"

          if [ ! -s "$config_path" ]; then
            echo "Duplicati R2: config $config_path not found or empty" >&2
            exit 1
          fi

          target_json=$(jq --arg slug "$slug" -c '.targets[$slug] // empty' "$config_path")
          if [ -z "$target_json" ] || [ "$target_json" = "null" ]; then
            echo "Duplicati R2: unknown target $slug" >&2
            exit 1
          fi

          env_file=$(jq -r '.environmentFile // empty' "$config_path")
          if [ -z "$env_file" ] || [ "$env_file" = "null" ]; then
            env_file="''${DUPLICATI_R2_DEFAULT_ENV_FILE:-/etc/duplicati/r2.env}"
          fi
          if [ ! -f "$env_file" ]; then
            echo "Duplicati R2: missing environment file $env_file" >&2
            exit 1
          fi

          bucket=$(jq -r '.bucket // empty' "$config_path")
          if [ -z "$bucket" ] || [ "$bucket" = "null" ]; then
            bucket="''${DUPLICATI_R2_DEFAULT_BUCKET:-duplicati-nixos-backups}"
          fi

          manifest_hostname=$(jq -r '.hostname // empty' "$config_path")
          if [ -n "$manifest_hostname" ] && [ "$manifest_hostname" != "null" ]; then
            hostname="$manifest_hostname"
          elif [ -n "''${DEFAULT_HOSTNAME:-}" ]; then
            hostname="''${DEFAULT_HOSTNAME}"
          else
            hostname=$(hostname --short 2>/dev/null || hostname 2>/dev/null || echo duplicati)
          fi

          dest_subpath=$(jq -r '.destSubpath // empty' <<<"$target_json")
          if [ -z "$dest_subpath" ]; then
            dest_subpath="$slug"
          fi

          samples="''${DUPLICATI_R2_VERIFY_SAMPLES:-200}"

          # shellcheck disable=SC1090
          . "$env_file"

          export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AUTH_USERNAME="$AWS_ACCESS_KEY_ID" AUTH_PASSWORD="$AWS_SECRET_ACCESS_KEY"

          if [ -n "''${R2_S3_ENDPOINT_URL:-}" ]; then
            export AWS_ENDPOINT_URL="''${R2_S3_ENDPOINT_URL}"
          elif [ -n "''${R2_S3_ENDPOINT:-}" ]; then
            export AWS_ENDPOINT_URL="https://''${R2_S3_ENDPOINT}"
          fi

          if [ -z "''${DUPLICATI_PASSPHRASE:-}" ]; then
            echo "Duplicati R2: DUPLICATI_PASSPHRASE missing from environment" >&2
            exit 1
          fi
          export PASSPHRASE="''${DUPLICATI_PASSPHRASE}"

          if [ -z "''${AWS_REGION:-}" ] && [ -z "''${AWS_DEFAULT_REGION:-}" ]; then
            if [ -n "''${R2_REGION:-}" ]; then
              export AWS_REGION="''${R2_REGION}"
              export AWS_DEFAULT_REGION="''${R2_REGION}"
            else
              export AWS_REGION=auto
              export AWS_DEFAULT_REGION=auto
            fi
          fi

          encoded_subpath=$(jq -nr --arg s "$dest_subpath" '$s | @uri')

          server_param=""
          if [ -n "''${R2_S3_ENDPOINT:-}" ]; then
            server_param="&s3-server-name=$R2_S3_ENDPOINT"
          elif [ -n "''${R2_S3_ENDPOINT_URL:-}" ]; then
            server_host=$(printf '%s\n' "''${R2_S3_ENDPOINT_URL}" | sed -E 's#^https?://##')
            server_param="&s3-server-name=$server_host"
          elif [ -n "$AWS_ENDPOINT_URL" ]; then
            server_host=$(printf '%s\n' "$AWS_ENDPOINT_URL" | sed -E 's#^https?://##')
            server_param="&s3-server-name=$server_host"
          fi

          region_suffix=""
          if [ -n "''${R2_REGION:-}" ]; then
            region_suffix="&s3-ext-region=$R2_REGION"
          fi

          dest="s3://$bucket/$hostname/$encoded_subpath?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio''${server_param}''${region_suffix}"

          exec ${cfg.package}/bin/duplicati-cli test "$dest" --samples="$samples"
        '';
      };

      generatorScript = pkgs.writeShellApplication {
        name = "duplicati-r2-generate-units";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.systemd
        ];
        text = ''
                    set -euo pipefail

                    config_source="''${DUPLICATI_R2_CONFIG_SOURCE:?}"
                    config_dest="''${DUPLICATI_R2_CONFIG_DEST:?}"
                    backup_exec="''${DUPLICATI_R2_BACKUP_EXEC:?}"
                    verify_exec="''${DUPLICATI_R2_VERIFY_EXEC:?}"
                    default_bucket="''${DUPLICATI_R2_DEFAULT_BUCKET:-duplicati-nixos-backups}"
                    default_state_dir="''${DUPLICATI_R2_DEFAULT_STATE_DIR:-/var/lib/duplicati-r2}"
                    default_env_file="''${DUPLICATI_R2_DEFAULT_ENV_FILE:-/etc/duplicati/r2.env}"
                    verify_samples_default="''${DUPLICATI_R2_VERIFY_SAMPLES_DEFAULT:-200}"

                    unit_dir=/run/systemd/system
                    mkdir -p "$unit_dir"
                    mkdir -p "$(dirname "$config_dest")"

                    if [ "$config_source" != "$config_dest" ]; then
                      if [ -s "$config_source" ]; then
                        install -D -m 0400 "$config_source" "$config_dest"
                      else
                        rm -f "$config_dest"
                      fi
                    fi

                    cleanup_units() {
                      local pattern="$1"
                      local unit
                      shopt -s nullglob
                      for unit in "$unit_dir"/$pattern; do
                        if [[ -e "$unit" ]]; then
                          local base
                          base="$(basename "$unit")"
                          if [[ "$base" == *.timer ]]; then
                            systemctl stop "$base" 2>/dev/null || true
                            systemctl disable --runtime "$base" 2>/dev/null || true
                          elif [[ "$base" == *.service ]]; then
                            systemctl stop "$base" 2>/dev/null || true
                            systemctl disable --runtime "$base" 2>/dev/null || true
                          fi
                          rm -f "$unit"
                        fi
                      done
                      shopt -u nullglob
                    }

                    cleanup_units 'duplicati-r2-backup-*.service'
                    cleanup_units 'duplicati-r2-backup-*.timer'
                    cleanup_units 'duplicati-r2-verify-*.service'
                    cleanup_units 'duplicati-r2-verify-*.timer'

                    if [ ! -s "$config_dest" ]; then
                      systemctl daemon-reload
                      exit 0
                    fi

                    mapfile -t entries < <(jq -r '.targets // {} | to_entries[] | @base64' "$config_dest")

                    if [ "''${#entries[@]}" -eq 0 ]; then
                      systemctl daemon-reload
                      exit 0
                    fi

                    bucket=$(jq -r '.bucket // empty' "$config_dest")
                    if [ -z "$bucket" ] || [ "$bucket" = "null" ]; then
                      bucket="$default_bucket"
                    fi

                    state_dir=$(jq -r '.stateDir // empty' "$config_dest")
                    if [ -z "$state_dir" ] || [ "$state_dir" = "null" ]; then
                      state_dir="$default_state_dir"
                    fi

                    mkdir -p "$state_dir"

                    env_file=$(jq -r '.environmentFile // empty' "$config_dest")
                    if [ -z "$env_file" ] || [ "$env_file" = "null" ]; then
                      env_file="$default_env_file"
                    fi

                    manifest_hostname=$(jq -r '.hostname // empty' "$config_dest")
                    if [ -z "$manifest_hostname" ] || [ "$manifest_hostname" = "null" ]; then
                      manifest_hostname=""
                    fi

                    verify_oncalendar=$(jq -r '.verify.onCalendar // empty' "$config_dest")
                    verify_samples=$(jq -r '.verify.samples // empty' "$config_dest")
                    if [ -z "$verify_samples" ] || [ "$verify_samples" = "null" ]; then
                      verify_samples="$verify_samples_default"
                    fi

                    backup_timers=()
                    verify_timers=()

          for encoded in "''${entries[@]}"; do
            entry=$(echo "$encoded" | base64 --decode)
            slug=$(echo "$entry" | jq -r '.key')
            schedule=$(echo "$entry" | jq -r '.value.onCalendar // .value.schedule // empty')
            [ -n "$schedule" ] || {
              echo "duplicati-r2 generator: target $slug missing onCalendar" >&2
              continue
            }

            slug_safe=$(printf '%s' "$slug" | tr -c 'A-Za-z0-9_-' '-')
            while [ "''${slug_safe#-}" != "$slug_safe" ]; do slug_safe="''${slug_safe#-}"; done
            while [ "''${slug_safe%-}" != "$slug_safe" ]; do slug_safe="''${slug_safe%-}"; done
            if [ -z "$slug_safe" ]; then
              slug_safe="target"
            fi

            service="duplicati-r2-backup-$slug_safe.service"
            timer="duplicati-r2-backup-$slug_safe.timer"

                      cat > "$unit_dir/$service" <<EOF
          [Unit]
          Description=Duplicati R2 backup ($slug)
          After=network-online.target sops-install-secrets.service
          Requires=sops-install-secrets.service
          Wants=network-online.target

          [Service]
          Type=oneshot
          Environment=DUPLICATI_R2_CONFIG=$config_dest
          Environment=DUPLICATI_R2_TARGET=$slug
          Environment=DUPLICATI_R2_DEFAULT_BUCKET=$bucket
          Environment=DUPLICATI_R2_DEFAULT_STATE_DIR=$state_dir
          Environment=DUPLICATI_R2_DEFAULT_ENV_FILE=$env_file
          $(if [ -n "$manifest_hostname" ]; then echo "Environment=DEFAULT_HOSTNAME=$manifest_hostname"; fi)
          ExecStart=$backup_exec
          EOF

                      cat > "$unit_dir/$timer" <<EOF
          [Unit]
          Description=Schedule Duplicati R2 backup ($slug)

          [Timer]
          OnCalendar=$schedule
          Persistent=true
          Unit=$service

          [Install]
          WantedBy=timers.target
          EOF

                      backup_timers+=("$timer")

            if [ -n "$verify_oncalendar" ]; then
              verify_service="duplicati-r2-verify-$slug_safe.service"
              verify_timer="duplicati-r2-verify-$slug_safe.timer"

                        cat > "$unit_dir/$verify_service" <<EOF
          [Unit]
          Description=Duplicati R2 verification ($slug)
          After=network-online.target sops-install-secrets.service
          Requires=sops-install-secrets.service
          Wants=network-online.target

          [Service]
          Type=oneshot
          Environment=DUPLICATI_R2_CONFIG=$config_dest
          Environment=DUPLICATI_R2_TARGET=$slug
          Environment=DUPLICATI_R2_DEFAULT_BUCKET=$bucket
          Environment=DUPLICATI_R2_DEFAULT_ENV_FILE=$env_file
          Environment=DUPLICATI_R2_VERIFY_SAMPLES=$verify_samples
          $(if [ -n "$manifest_hostname" ]; then echo "Environment=DEFAULT_HOSTNAME=$manifest_hostname"; fi)
          ExecStart=$verify_exec
          EOF

                        cat > "$unit_dir/$verify_timer" <<EOF
          [Unit]
          Description=Schedule Duplicati R2 verification ($slug)

          [Timer]
          OnCalendar=$verify_oncalendar
          Persistent=true
          Unit=$verify_service

          [Install]
          WantedBy=timers.target
          EOF

                        verify_timers+=("$verify_timer")
                      fi
                    done

                    systemctl daemon-reload

                    for timer in "''${backup_timers[@]}"; do
                      if ! systemctl enable --runtime "$timer" >/dev/null; then
                        echo "Failed to enable systemd timer $timer" >&2
                        exit 1
                      fi
                      if ! systemctl start "$timer" >/dev/null; then
                        echo "Failed to start systemd timer $timer" >&2
                        exit 1
                      fi
                    done

                    for timer in "''${verify_timers[@]}"; do
                      if ! systemctl enable --runtime "$timer" >/dev/null; then
                        echo "Failed to enable systemd timer $timer" >&2
                        exit 1
                      fi
                      if ! systemctl start "$timer" >/dev/null; then
                        echo "Failed to start systemd timer $timer" >&2
                        exit 1
                      fi
                    done
        '';
      };
    in
    {
      options.services.duplicati-r2 = {
        enable = mkEnableOption "Duplicati R2 backup services";

        package = mkPackageOption pkgs "duplicati" { };

        configFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            Path to a SOPS-encrypted JSON manifest describing backup targets.
            When set, the file is decrypted via sops.templates during activation
            so the plaintext never enters the Nix store.
          '';
          example = literalExpression "inputs.secrets + \"/duplicati-config.json\"";
        };

        environmentFile = mkOption {
          type = types.path;
          default = "/etc/duplicati/r2.env";
          description = "Location of the rendered environment file containing R2 credentials.";
        };

        stateDir = mkOption {
          type = types.path;
          default = "/var/lib/duplicati-r2";
          description = "Root directory for Duplicati state (per-target SQLite databases).";
        };

        bucket = mkOption {
          type = types.str;
          default = "duplicati-nixos-backups";
          description = "Cloudflare R2 bucket name used for backups.";
        };

        hostname = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Optional hostname override for destination layout. Defaults to the
            system's networking.hostName when unset.
          '';
        };

        credentials = mkOption {
          type = types.attrsOf credentialModule;
          default = defaultCredentials;
          description = ''
            Mapping from environment variable names to SOPS selectors resolving
            to credential values in <filename>secrets/duplicati-r2.yaml</filename>.
          '';
          example = literalExpression ''
            let
              prefix = "my-r2/";
            in {
              AWS_ACCESS_KEY_ID.secret = prefix + ("aws" + "AccessKeyId");
              AWS_SECRET_ACCESS_KEY.secret = prefix + ("awsSecret" + "AccessKey");
            }
          '';
        };

        targets = mkOption {
          type = types.attrsOf targetModule;
          default = { };
          description = "Declarative backup targets rendered into the runtime manifest when no external configFile is supplied.";
        };

        verify = mkOption {
          type = types.nullOr verifyModule;
          default = null;
          description = "Optional verification schedule applied per target.";
        };
      };

      config = mkIf cfg.enable (
        let
          secretsDeclared = mapAttrs' (
            envName: value:
            let
              selector = value.secret;
            in
            lib.nameValuePair "duplicati-r2/${envName}" {
              sopsFile = credentialsSecretPath;
              format = "yaml";
              key = selector;
              mode = "0400";
              owner = "root";
            }
          ) cfg.credentials;
        in
        {
          assertions = [
            {
              assertion = credentialsExist;
              message = "services.duplicati-r2 requires secrets/duplicati-r2.yaml (encrypted via sops).";
            }
            {
              assertion = builtins.substring 0 1 (toString cfg.environmentFile) == "/";
              message = "services.duplicati-r2.environmentFile must be an absolute path.";
            }
            {
              assertion = builtins.substring 0 1 (toString cfg.stateDir) == "/";
              message = "services.duplicati-r2.stateDir must be an absolute path.";
            }
            {
              assertion = usingSecret || cfg.targets != { };
              message = "services.duplicati-r2.targets must define at least one entry when no configFile is supplied.";
            }
            {
              assertion =
                (!usingSecret)
                || (cfg.configFile != null && builtins.substring 0 1 (toString cfg.configFile) == "/");
              message = "services.duplicati-r2.configFile must be an absolute path when provided.";
            }
            {
              assertion = (!usingSecret) || builtins.pathExists cfg.configFile;
              message = "services.duplicati-r2.configFile points to a missing encrypted manifest.";
            }
          ];

          environment.systemPackages = [ cfg.package ];

          sops.secrets = lib.mkMerge [
            secretsDeclared
            (mkIf usingSecret {
              "duplicati-r2/manifest" = {
                sopsFile = cfg.configFile;
                format = "binary";
                mode = "0400";
                owner = "root";
              };
            })
          ];

          sops.templates = lib.mkMerge [
            {
              "duplicati-r2-env" = {
                path = cfg.environmentFile;
                mode = "0400";
                owner = "root";
                group = "root";
                restartUnits = [ "${generatorServiceName}.service" ];
                content =
                  let
                    renderEnv =
                      envName:
                      let
                        placeholderKey = "duplicati-r2/${envName}";
                      in
                      "${envName}=${config.sops.placeholder.${placeholderKey}}";
                  in
                  concatStringsSep "\n" (mapAttrsToList (envName: _: renderEnv envName) cfg.credentials) + "\n";
              };
            }
            (mkIf usingSecret {
              ${manifestTemplateName} = {
                path = manifestDest;
                mode = "0400";
                owner = "root";
                group = "root";
                restartUnits = [ "${generatorServiceName}.service" ];
                content = config.sops.placeholder."duplicati-r2/manifest";
              };
            })
          ];

          systemd.services.${generatorServiceName} = {
            description = "Generate Duplicati R2 systemd units";
            after = [
              "sops-install-secrets.service"
              "network-online.target"
            ];
            requires = [ "sops-install-secrets.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            restartTriggers = [
              manifestSource
              backupScript
              verifyScript
            ];
            environment = {
              DUPLICATI_R2_CONFIG_SOURCE = manifestSource;
              DUPLICATI_R2_CONFIG_DEST = manifestDest;
              DUPLICATI_R2_BACKUP_EXEC = "${backupScript}/bin/duplicati-r2-backup";
              DUPLICATI_R2_VERIFY_EXEC = "${verifyScript}/bin/duplicati-r2-verify";
              DUPLICATI_R2_DEFAULT_BUCKET = defaultBucket;
              DUPLICATI_R2_DEFAULT_STATE_DIR = defaultStateDir;
              DUPLICATI_R2_DEFAULT_ENV_FILE = defaultEnvFile;
              DUPLICATI_R2_VERIFY_SAMPLES_DEFAULT =
                if cfg.verify != null then builtins.toString cfg.verify.samples else "200";
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${generatorScript}/bin/duplicati-r2-generate-units";
            };
          };

          systemd.tmpfiles.rules = [
            "d ${cfg.stateDir} 0700 root root - -"
          ];
        }
      );
    };
in
{
  flake.nixosModules.services.duplicati-r2 = module;
  flake.nixosModules."duplicati-r2" = module;
}
