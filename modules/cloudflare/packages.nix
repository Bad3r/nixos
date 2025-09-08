{
  # Cloudflare tooling bundle
  #
  # Adds commonly used Cloudflare CLIs and helpers to the system PATH.
  # All tools are sourced from nixpkgs to keep things reproducible.
  #
  # Included tools:
  # - wrangler: Workers/Pages/Durable Objects/D1/R2/Queues CLI
  #   Docs: https://developers.cloudflare.com/workers/wrangler/
  # - flarectl: Cloudflare API CLI (zones, DNS, WAF, LB, analytics)
  #   Docs: https://github.com/cloudflare/cloudflare-go/tree/master/cmd/flarectl
  # - terraform: Terraform core
  #   Docs: https://developer.hashicorp.com/terraform/docs
  # - cf-terraforming: Export existing Cloudflare resources to Terraform HCL
  #   Docs: https://github.com/cloudflare/cf-terraforming
  # - cloudflared: Cloudflare Tunnel client
  #   Docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
  # - wgcf: Unofficial WARP config generator (useful for dev)
  #   Repo: https://github.com/ViRb3/wgcf
  # - rclone: S3/R2 sync and copy tool
  #   Docs: https://rclone.org/s3/
  # - s5cmd: High-performance S3 CLI for large transfers (works with R2)
  #   Repo: https://github.com/peak/s5cmd
  # - minio-client (mc): S3-compatible object storage CLI (works with R2)
  #   Docs: https://min.io/docs/minio/linux/reference/minio-mc.html
  # - awscli2: Generic S3 CLI (use custom endpoint for R2)
  #   Docs: https://developers.cloudflare.com/r2/terraform-and-cli/cli/
  # - worker-build: Rust Workers build helper (for workers-rs projects)
  #   Repo: https://github.com/cloudflare/workers-rs/tree/main/worker-build
  # - jq, xh: JSON and HTTP CLIs used to script Cloudflare APIs
  #   jq: https://jqlang.github.io/jq/
  #   xh: https://github.com/ducaale/xh
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        wrangler
        flarectl
        terraform
        cf-terraforming
        cloudflared
        cloudflare-warp # WARP CLI binaries available; service not enabled by default
        wgcf
        rclone
        s5cmd
        minio-client
        awscli2
        worker-build
        jq
        xh
      ];

      # Optional helpful note at evaluation time
      assertions = [
        {
          assertion = true;
          message = ''
            Cloudflare tools are installed. See:
            - Wrangler: https://developers.cloudflare.com/workers/wrangler/
            - Tunnels: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
            - Terraforming: https://github.com/cloudflare/cf-terraforming
            - R2 via rclone: https://rclone.org/s3/
          '';
        }
      ];
    };
}
