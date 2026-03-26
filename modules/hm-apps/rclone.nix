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
      gdriveSecretContents = if gdriveSecretExists then builtins.readFile gdriveSecretFile else "";
      gdriveTokenExists = lib.hasInfix "GDRIVE_TOKEN=" gdriveSecretContents;
      renderedRcloneConfig = "${config.xdg.configHome}/rclone/rclone.conf";
    in
    {
      config = lib.mkIf nixosEnabled (
        lib.mkMerge [
          {
            programs.rclone = {
              enable = true;
              # Package installed by NixOS module (not overridable here)
            };
          }

          (lib.mkIf gdriveSecretExists {
            sops.secrets."rclone/gdrive-env" = {
              sopsFile = gdriveSecretFile;
              format = "dotenv";
              mode = "0400";
            };

            home.activation.configureRcloneConfig = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
              gdriveEnvPath=${lib.escapeShellArg config.sops.secrets."rclone/gdrive-env".path}
              renderedConfig=${lib.escapeShellArg renderedRcloneConfig}
              renderedDir="$(dirname "$renderedConfig")"

              run mkdir -p "$renderedDir"
              chmod 700 "$renderedDir"
              tmpConfig="$(mktemp "$renderedDir/rclone.conf.XXXXXX")"
              trap 'rm -f "$tmpConfig"' EXIT

              unset GDRIVE_CLIENT_ID GDRIVE_CLIENT_SECRET GDRIVE_TOKEN
              . "$gdriveEnvPath"

              if [ -z "$GDRIVE_CLIENT_ID" ] || [ -z "$GDRIVE_CLIENT_SECRET" ]; then
                echo "rclone gdrive env file is missing GDRIVE_CLIENT_ID or GDRIVE_CLIENT_SECRET: $gdriveEnvPath" >&2
                exit 1
              fi

              {
                printf '[r2]\n'
                printf 'type = s3\n'
                printf 'provider = Cloudflare\n'
                printf 'env_auth = true\n\n'
                printf '[gdrive]\n'
                printf 'type = drive\n'
                printf 'client_id = %s\n' "$GDRIVE_CLIENT_ID"
                printf 'client_secret = %s\n' "$GDRIVE_CLIENT_SECRET"
                printf 'scope = drive\n'
                if [ -n "''${GDRIVE_TOKEN:-}" ]; then
                  printf 'token = %s\n' "$GDRIVE_TOKEN"
                fi
              } > "$tmpConfig"

              chmod 600 "$tmpConfig"
              run mv "$tmpConfig" "$renderedConfig"
            '';
          })

          (lib.mkIf (!gdriveSecretExists) {
            warnings = [
              "programs.rclone.extended.enable is true but ${gdriveSecretFile} is missing; skipping gdrive remote setup."
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
