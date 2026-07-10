/*
  Package: rclone
  Description: Command-line cloud storage sync utility supporting many providers.
  Homepage: https://rclone.org/
*/

_: {
  flake.homeManagerModules.apps.rclone =
    {
      config,
      osConfig,
      lib,
      secretsRoot,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "rclone" "extended" "enable" ] false osConfig;
      gdriveSecretFile = "${secretsRoot}/rclone_gdrive.env";
      gdriveSecretExists = builtins.pathExists gdriveSecretFile;
      gdriveEnvPath = lib.attrByPath [ "sops" "secrets" "rclone/gdrive-env" "path" ] null osConfig;
      repoSecretsEnabled = lib.attrByPath [ "security" "repoSecrets" "enable" ] true osConfig;
      gdriveSecretContents = if gdriveSecretExists then builtins.readFile gdriveSecretFile else "";
      gdriveTokenExists = lib.hasInfix "GDRIVE_TOKEN=" gdriveSecretContents;
      gdriveReady = gdriveSecretExists && repoSecretsEnabled && gdriveEnvPath != null;
      protondriveSecretFile = "${secretsRoot}/rclone_protondrive.env";
      protondriveSecretExists = builtins.pathExists protondriveSecretFile;
      protondriveEnvPath = lib.attrByPath [
        "sops"
        "secrets"
        "rclone/protondrive-env"
        "path"
      ] null osConfig;
      protondriveReady = protondriveSecretExists && repoSecretsEnabled && protondriveEnvPath != null;
      r2SecretFile = "${secretsRoot}/r2.yaml";
      r2SecretExists = builtins.pathExists r2SecretFile;
      r2SecretsEnabled = lib.attrByPath [ "home" "r2Secrets" "enable" ] false config;
      r2EndpointAvailable = r2SecretsEnabled && r2SecretExists;
      renderedRcloneConfig = "${config.xdg.configHome}/rclone/rclone.conf";
      # Ownership guard inputs. The r2-flake Home Manager module declares
      # programs.r2-cloud only when a host policy imports it, so probe with
      # attrByPath instead of reading undeclared options.
      r2CloudCfg = lib.attrByPath [ "programs" "r2-cloud" ] { } config;
      r2CloudRcloneConfigPath =
        if r2CloudCfg ? rcloneConfigPath then toString r2CloudCfg.rcloneConfigPath else "";
      r2CloudClaimsRenderedConfig =
        (r2CloudCfg.enable or false)
        && (r2CloudCfg.enableRcloneRemote or false)
        && r2CloudRcloneConfigPath == renderedRcloneConfig;
    in
    {
      config = lib.mkIf nixosEnabled (
        lib.mkMerge [
          {
            # This module is the single writer of renderedRcloneConfig while
            # programs.rclone.extended.enable is set; other generators must
            # target a different path (see docs/r2-cloud/home-manager-r2-cloud.md).
            assertions = [
              {
                assertion = !r2CloudClaimsRenderedConfig;
                message = "programs.rclone.extended.enable makes modules/hm-apps/rclone.nix the owner of ${renderedRcloneConfig}, but programs.r2-cloud.enableRcloneRemote also renders programs.r2-cloud.rcloneConfigPath = ${r2CloudRcloneConfigPath}. Set programs.r2-cloud.enableRcloneRemote = false (as modules/lib/r2-runtime.nix does) or point programs.r2-cloud.rcloneConfigPath at a different file.";
              }
              {
                assertion = config.programs.rclone.remotes == { };
                message = "programs.rclone.remotes would make the upstream Home Manager rclone-config generator a second writer of ${renderedRcloneConfig} next to the activation writer in modules/hm-apps/rclone.nix. Keep remotes empty or retire the activation writer first.";
              }
            ];

            programs.rclone = {
              enable = true;
            };

            home.activation.configureRcloneConfig = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
              renderedConfig=${lib.escapeShellArg renderedRcloneConfig}
              renderedDir="$(dirname "$renderedConfig")"
              endpointFile=${
                lib.escapeShellArg (
                  if r2EndpointAvailable then config.sops.templates."rclone/r2-endpoint".path else ""
                )
              }
              gdriveEnabled=${lib.boolToString gdriveReady}
              gdriveEnvPath=${lib.escapeShellArg (if gdriveReady then gdriveEnvPath else "")}
              protondriveEnabled=${lib.boolToString protondriveReady}
              protondriveEnvPath=${lib.escapeShellArg (if protondriveReady then protondriveEnvPath else "")}

              run mkdir -p "$renderedDir"
              chmod 700 "$renderedDir"
              tmpConfig="$(mktemp "$renderedDir/rclone.conf.XXXXXX")"
              trap 'rm -f "$tmpConfig"' EXIT

              {
                printf '[r2]\n'
                printf 'type = s3\n'
                printf 'provider = Cloudflare\n'
                printf 'env_auth = true\n'
                if [ -n "$endpointFile" ] && [ -r "$endpointFile" ]; then
                  printf 'endpoint = %s\n' "$(cat "$endpointFile")"
                fi
              } > "$tmpConfig"

              if [ "$gdriveEnabled" = true ]; then
                # The sops secret may not be materialized yet on a first
                # activation; skip with a warning instead of aborting the
                # whole home-manager activation under set -eu.
                if [ ! -r "$gdriveEnvPath" ]; then
                  echo "rclone gdrive env file is missing or unreadable at $gdriveEnvPath; skipping gdrive remote refresh for this activation" >&2
                  # Carry the previously rendered [gdrive] stanza forward so a
                  # transiently unreadable secret does not drop a working
                  # remote from the rewritten config.
                  if [ -r "$renderedConfig" ]; then
                    prevGdrive="$(sed -n '/^\[gdrive\]$/,/^\[/{ /^\[gdrive\]$/p; /^\[/!p; }' "$renderedConfig")"
                    if [ -n "$prevGdrive" ]; then
                      printf '\n%s\n' "$prevGdrive" >> "$tmpConfig"
                      echo "rclone gdrive remote preserved from the previous rendered config" >&2
                    fi
                  fi
                else
                  unset GDRIVE_CLIENT_ID GDRIVE_CLIENT_SECRET GDRIVE_TOKEN
                  . "$gdriveEnvPath"

                  if [ -z "''${GDRIVE_CLIENT_ID:-}" ] || [ -z "''${GDRIVE_CLIENT_SECRET:-}" ]; then
                    echo "rclone gdrive env file is missing GDRIVE_CLIENT_ID or GDRIVE_CLIENT_SECRET: $gdriveEnvPath" >&2
                    exit 1
                  fi

                  {
                    printf '\n[gdrive]\n'
                    printf 'type = drive\n'
                    printf 'client_id = %s\n' "$GDRIVE_CLIENT_ID"
                    printf 'client_secret = %s\n' "$GDRIVE_CLIENT_SECRET"
                    printf 'scope = drive\n'
                    if [ -n "''${GDRIVE_TOKEN:-}" ]; then
                      printf 'token = %s\n' "$GDRIVE_TOKEN"
                    fi
                  } >> "$tmpConfig"
                fi
              fi

              if [ "$protondriveEnabled" = true ]; then
                # Mirror the gdrive guard: the sops secret may be unmaterialized
                # on a first activation, so skip with a warning instead of letting
                # `. "$protondriveEnvPath"` abort the whole home-manager activation
                # under set -eu.
                if [ ! -r "$protondriveEnvPath" ]; then
                  echo "rclone protondrive env file is missing or unreadable at $protondriveEnvPath; skipping protondrive remote refresh for this activation" >&2
                  # Carry the previously rendered [protondrive] stanza forward so a
                  # transiently unreadable secret does not drop a working remote.
                  if [ -r "$renderedConfig" ]; then
                    prevProton="$(sed -n '/^\[protondrive\]$/,/^\[/{ /^\[protondrive\]$/p; /^\[/!p; }' "$renderedConfig")"
                    if [ -n "$prevProton" ]; then
                      printf '\n%s\n' "$prevProton" >> "$tmpConfig"
                      echo "rclone protondrive remote preserved from the previous rendered config" >&2
                    fi
                  fi
                else
                  unset PROTONDRIVE_USERNAME PROTONDRIVE_PASSWORD PROTONDRIVE_OTP_SECRET_KEY PROTONDRIVE_MAILBOX_PASSWORD
                  . "$protondriveEnvPath"

                  if [ -z "''${PROTONDRIVE_USERNAME:-}" ] || [ -z "''${PROTONDRIVE_PASSWORD:-}" ]; then
                    echo "rclone protondrive env file is missing PROTONDRIVE_USERNAME or PROTONDRIVE_PASSWORD: $protondriveEnvPath" >&2
                    exit 1
                  fi

                  # password/otp_secret_key/mailbox_password must already be rclone-obscured
                  # in the secret (run `rclone obscure <value>`); the backend reveals them.
                  # enable_caching is forced off: required for `rclone mount` (Proton's
                  # change-event system is unimplemented, so a metadata cache goes stale)
                  # and harmless for bisync.
                  {
                    printf '\n[protondrive]\n'
                    printf 'type = protondrive\n'
                    printf 'username = %s\n' "$PROTONDRIVE_USERNAME"
                    printf 'password = %s\n' "$PROTONDRIVE_PASSWORD"
                    if [ -n "''${PROTONDRIVE_OTP_SECRET_KEY:-}" ]; then
                      printf 'otp_secret_key = %s\n' "$PROTONDRIVE_OTP_SECRET_KEY"
                    fi
                    if [ -n "''${PROTONDRIVE_MAILBOX_PASSWORD:-}" ]; then
                      printf 'mailbox_password = %s\n' "$PROTONDRIVE_MAILBOX_PASSWORD"
                    fi
                    printf 'enable_caching = false\n'
                  } >> "$tmpConfig"
                fi
              fi

              chmod 600 "$tmpConfig"
              run mv "$tmpConfig" "$renderedConfig"
            '';
          }

          (lib.mkIf r2EndpointAvailable {
            sops.templates."rclone/r2-endpoint" = {
              content = ''
                https://${config.sops.placeholder."cloudflare/r2/account-id"}.r2.cloudflarestorage.com
              '';
              mode = "0400";
            };
          })

          (lib.mkIf (gdriveSecretExists && (!repoSecretsEnabled)) {
            warnings = [
              "programs.rclone.extended.enable is true and ${gdriveSecretFile} exists, but security.repoSecrets.enable is false on this host; skipping gdrive remote setup. Manage ~/.config/rclone/rclone.conf manually or enable repo secrets after SOPS decryption is configured."
            ];
          })

          (lib.mkIf (gdriveSecretExists && repoSecretsEnabled && gdriveEnvPath == null) {
            warnings = [
              "programs.rclone.extended.enable is true and ${gdriveSecretFile} exists, but no system-side rclone/gdrive-env secret path was declared in osConfig; skipping gdrive remote setup."
            ];
          })

          (lib.mkIf (gdriveSecretExists && !gdriveTokenExists) {
            warnings = [
              "rclone gdrive credentials were loaded from ${gdriveSecretFile}, but no GDRIVE_TOKEN was found. Obtain a Drive token with a temporary rclone config or `rclone authorize drive <client_id> <client_secret>`, then store the resulting JSON as GDRIVE_TOKEN in ${gdriveSecretFile}."
            ];
          })

          (lib.mkIf (protondriveSecretExists && (!repoSecretsEnabled)) {
            warnings = [
              "programs.rclone.extended.enable is true and ${protondriveSecretFile} exists, but security.repoSecrets.enable is false on this host; skipping protondrive remote setup. Manage ~/.config/rclone/rclone.conf manually or enable repo secrets after SOPS decryption is configured."
            ];
          })

          (lib.mkIf (protondriveSecretExists && repoSecretsEnabled && protondriveEnvPath == null) {
            warnings = [
              "programs.rclone.extended.enable is true and ${protondriveSecretFile} exists, but no system-side rclone/protondrive-env secret path was declared in osConfig; skipping protondrive remote setup."
            ];
          })
        ]
      );
    };
}
