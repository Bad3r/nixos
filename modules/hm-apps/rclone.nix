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
      r2SecretFile = "${secretsRoot}/r2.yaml";
      r2SecretExists = builtins.pathExists r2SecretFile;
      r2SecretsEnabled = lib.attrByPath [ "home" "r2Secrets" "enable" ] false config;
      r2EndpointAvailable = r2SecretsEnabled && r2SecretExists;
      renderedRcloneConfig = "${config.xdg.configHome}/rclone/rclone.conf";
    in
    {
      config = lib.mkIf nixosEnabled (
        lib.mkMerge [
          {
            programs.r2-cloud.enableRcloneRemote = lib.mkForce false;

            programs.rclone = {
              enable = true;
              # Package installed by NixOS module (not overridable here)
            };

            home.activation.configureRcloneConfig = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
              renderedConfig=${lib.escapeShellArg renderedRcloneConfig}
              renderedDir="$(dirname "$renderedConfig")"
              endpointFile=${
                lib.escapeShellArg (
                  if r2EndpointAvailable then config.sops.templates."rclone/r2-endpoint".path else ""
                )
              }
              gdriveEnabled=${lib.boolToString gdriveSecretExists}

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
                gdriveEnvPath=${lib.escapeShellArg config.sops.secrets."rclone/gdrive-env".path}

                unset GDRIVE_CLIENT_ID GDRIVE_CLIENT_SECRET GDRIVE_TOKEN
                . "$gdriveEnvPath"

                if [ -z "$GDRIVE_CLIENT_ID" ] || [ -z "$GDRIVE_CLIENT_SECRET" ]; then
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

              chmod 600 "$tmpConfig"
              run mv "$tmpConfig" "$renderedConfig"
            '';
          }

          (lib.mkIf gdriveSecretExists {
            sops.secrets."rclone/gdrive-env" = {
              sopsFile = gdriveSecretFile;
              format = "dotenv";
              mode = "0400";
            };
          })

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
        ]
      );
    };
}
