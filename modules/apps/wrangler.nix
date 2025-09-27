/*
  Package: wrangler
  Description: Cloudflare Workers CLI for developing, testing, and deploying serverless functions.
  Homepage: https://developers.cloudflare.com/workers/wrangler/
  Documentation: https://developers.cloudflare.com/workers/wrangler/cli-reference/
  Repository: https://github.com/cloudflare/workers-sdk

  Summary:
    * Manages project scaffolding, local previews, secret storage, and deployments for Cloudflare Workers and Pages.
    * Supports type generation, Durable Objects migrations, and remote logs through the Workers platform.

  Options:
    --env <name>: Target a specific deployment environment for commands such as `wrangler deploy --env staging`.
    --dry-run: Preview deployments without pushing changes when combined with `wrangler deploy --dry-run`.
    --minify: Enable JavaScript minification during builds via `wrangler deploy --minify`.
*/

{
  flake.nixosModules.apps.wrangler =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wrangler ];
    };
}
