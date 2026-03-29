/*
  Package: rclone
  Description: Command-line program to sync files and directories to cloud storage providers.
  Homepage: https://rclone.org/
  Documentation: https://rclone.org/docs/
  Repository: https://github.com/rclone/rclone

  Summary:
    * Synchronizes directories across over 70 cloud storage and S3-compatible providers with checksum verification.
    * Offers advanced features such as encryption, caching, chunked transfers, mounts, and HTTP serving.

  Options:
    --config <path>: Point rclone at an alternate configuration file containing remote definitions.
    --drive-server-side-across-configs: Enable server-side copies between Google Drive remotes when credentials permit.
    --transfers <n>: Limit the number of concurrent transfers to control bandwidth usage.
*/
_:
let
  RcloneModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      secretsRoot,
      ...
    }:
    let
      cfg = config.programs.rclone.extended;
      owner = metaOwner.username;
      gdriveSecretFile = "${secretsRoot}/rclone_gdrive.env";
      gdriveSecretExists = builtins.pathExists gdriveSecretFile;
      gdriveSecretPath = "/run/secrets/rclone/gdrive-env";
      repoSecretsEnabled = lib.attrByPath [ "security" "repoSecrets" "enable" ] true config;
    in
    {
      options.programs.rclone.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable rclone.";
        };

        package = lib.mkPackageOption pkgs "rclone" { };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];
        })

        (lib.mkIf (cfg.enable && gdriveSecretExists && repoSecretsEnabled) {
          sops.secrets."rclone/gdrive-env" = {
            sopsFile = gdriveSecretFile;
            format = "dotenv";
            path = gdriveSecretPath;
            inherit owner;
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && gdriveSecretExists && (!repoSecretsEnabled)) {
          warnings = [
            "programs.rclone.extended.enable is true and ${gdriveSecretFile} exists, but security.repoSecrets.enable is false on this host; skipping gdrive secret materialization. Manage rclone gdrive config manually or enable repo secrets after SOPS decryption is configured."
          ];
        })

        (lib.mkIf (cfg.enable && !gdriveSecretExists) {
          warnings = [
            "programs.rclone.extended.enable is true but ${gdriveSecretFile} is missing; skipping gdrive remote setup."
          ];
        })
      ];
    };
in
{
  flake.nixosModules.apps.rclone = RcloneModule;
}
