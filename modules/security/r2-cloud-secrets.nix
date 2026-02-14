{
  lib,
  metaOwner,
  secretsRoot,
  ...
}:
{
  # System-scoped declarations for Cloudflare R2 secrets sourced from
  # secrets/r2.yaml and rendered to /run/secrets/r2/*.
  flake.nixosModules.base =
    { config, ... }:
    let
      r2SecretFile = "${secretsRoot}/r2.yaml";
      r2SecretExists = builtins.pathExists r2SecretFile;
      ownerName = metaOwner.username;
    in
    {
      # sops-nix is imported centrally in modules/security/secrets.nix (base),
      # so this module only declares secrets/templates.
      config = lib.mkIf r2SecretExists {
        sops = {
          secrets = {
            "r2/account-id" = {
              sopsFile = r2SecretFile;
              format = "yaml";
              key = "account_id";
              path = "/run/secrets/r2/account-id";
              mode = "0400";
              owner = ownerName;
            };

            "r2/access-key-id" = {
              sopsFile = r2SecretFile;
              format = "yaml";
              key = "access_key_id";
              path = "/run/secrets/r2/access-key-id";
              mode = "0400";
              owner = ownerName;
            };

            "r2/secret-access-key" = {
              sopsFile = r2SecretFile;
              format = "yaml";
              key = "secret_access_key";
              path = "/run/secrets/r2/secret-access-key";
              mode = "0400";
              owner = ownerName;
            };

            "r2/restic-password" = {
              sopsFile = r2SecretFile;
              format = "yaml";
              key = "restic_password";
              path = "/run/secrets/r2/restic-password";
              mode = "0400";
              owner = ownerName;
            };

            # Worker admin signing credentials for `r2 share worker ...`.
            #
            # Keep these in SOPS and render them at runtime so the secret never
            # lands in the Nix store.
            "r2/explorer-admin-kid" = {
              sopsFile = r2SecretFile;
              format = "yaml";
              key = "explorer_admin_kid";
              path = "/run/secrets/r2/explorer-admin-kid";
              mode = "0400";
              owner = ownerName;
            };

            "r2/explorer-admin-secret" = {
              sopsFile = r2SecretFile;
              format = "yaml";
              key = "explorer_admin_secret";
              path = "/run/secrets/r2/explorer-admin-secret";
              mode = "0400";
              owner = ownerName;
            };
          };

          templates."r2-credentials.env" = {
            content = ''
              R2_ACCOUNT_ID=${config.sops.placeholder."r2/account-id"}
              AWS_ACCESS_KEY_ID=${config.sops.placeholder."r2/access-key-id"}
              AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."r2/secret-access-key"}
            '';
            path = "/run/secrets/r2/credentials.env";
            mode = "0400";
            owner = ownerName;
          };

          templates."r2-explorer.env" = {
            content = ''
              R2_EXPLORER_BASE_URL=https://files.unsigned.sh
              R2_EXPLORER_ADMIN_KID=${config.sops.placeholder."r2/explorer-admin-kid"}
              R2_EXPLORER_ADMIN_SECRET=${config.sops.placeholder."r2/explorer-admin-secret"}
            '';
            path = "/run/secrets/r2/explorer.env";
            mode = "0400";
            owner = ownerName;
          };
        };
      };
    };
}
