{
  # R2 quickstart profiles for rclone and s5cmd (examples only)
  #
  # This module provides example configuration files under /etc/cloudflare-r2
  # for interacting with Cloudflare R2 via S3-compatible tooling.
  #
  # IMPORTANT:
  # - Files include placeholders; do not store real secrets in Nix code.
  # - Copy these examples to user config locations and inject secrets via
  #   environment variables or secret-management tooling (e.g., sops-nix).
  #
  # R2 docs:
  # - CLI overview: https://developers.cloudflare.com/r2/terraform-and-cli/cli/
  # - S3 compatibility: https://developers.cloudflare.com/r2/api/s3/
  # rclone S3 docs: https://rclone.org/s3/
  # s5cmd docs: https://github.com/peak/s5cmd
  flake.modules.nixos.workstation = _: {
    environment.etc = {
      "cloudflare-r2/README".text = ''
        Cloudflare R2 quickstart files (examples)

        This directory contains sample configuration for rclone and s5cmd
        against R2 (S3-compatible). Replace placeholders as needed and
        copy the configs to your user environment. Do not store secrets here.

        R2 Docs: https://developers.cloudflare.com/r2/
      '';

      # rclone.conf example remote named "r2"
      "cloudflare-r2/rclone.conf.example".text = ''
        [r2]
        type = s3
        provider = Cloudflare
        # Replace with your R2 account ID:
        # See: https://developers.cloudflare.com/r2/api/s3/
        endpoint = https://<ACCOUNT_ID>.r2.cloudflarestorage.com

        # Recommended: provide credentials via env at runtime
        # export AWS_ACCESS_KEY_ID=...
        # export AWS_SECRET_ACCESS_KEY=...
        # Alternatively uncomment and place in a user config outside Nix:
        # access_key_id = <ACCESS_KEY_ID>
        # secret_access_key = <SECRET_ACCESS_KEY>
      '';

      # s5cmd environment example
      "cloudflare-r2/s5cmd.env.example".text = ''
        # Copy to a safe location and source before using s5cmd
        # export AWS_ACCESS_KEY_ID=...
        # export AWS_SECRET_ACCESS_KEY=...
        # For R2 set a custom endpoint URL (per-bucket or account level)
        # s5cmd takes endpoints as part of the URL you use, e.g.:
        #   s5cmd ls s3://<bucket>/ --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
        # Or set AWS_ENDPOINT_URL to avoid repeating:
        # export AWS_ENDPOINT_URL=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
      '';
    };
  };
}
