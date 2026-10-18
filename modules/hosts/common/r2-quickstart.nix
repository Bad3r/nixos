_:
let
  body = {
    environment.etc = {
      "cloudflare-r2/README".text = ''
        Cloudflare R2 quickstart files (examples)

        This directory contains sample configuration for rclone against R2
        (S3-compatible). Replace placeholders as needed and copy the config
        to your user environment. Do not store secrets here.

        Runtime credentials are rendered from secrets/r2.yaml to:
          /run/secrets/r2/credentials.env
        This file is owner-readable and can be sourced directly.

        R2 Docs: https://developers.cloudflare.com/r2/
      '';

      "cloudflare-r2/rclone.conf.example".text = ''
        [r2]
        type = s3
        provider = Cloudflare
        endpoint = https://<ACCOUNT_ID>.r2.cloudflarestorage.com

        # Recommended: provide credentials via env at runtime
        # export AWS_ACCESS_KEY_ID=...
        # export AWS_SECRET_ACCESS_KEY=...
        # Alternatively uncomment and place in a user config outside Nix:
        # access_key_id = <ACCESS_KEY_ID>
        # secret_access_key = <SECRET_ACCESS_KEY>
      '';
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
