# Cloudflare Tunnel Starter Configuration

This repository previously shipped a `modules/networking/cloudflared-tunnel.nix`
sample that enabled Cloudflare Tunnel with placeholder values. As part of the
single-host refactor, the workstation bundle is going away, so keep this example
in documentation instead of wiring it automatically.

```nix
{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "${exampleTunnelId}" = {
        credentialsFile = placeholderCreds;
        ingress = {
          "${exampleDomain}" = {
            service = "http://127.0.0.1:8080";
          };
        };
        default = "http_status:404";
      };
    };
  };
}
```

Fill in the following pieces before deploying:

1. Create a tunnel via `cloudflared tunnel create` and record the UUID.
2. Generate credentials JSON with Cloudflare tooling; mount it outside the store.
3. Replace `exampleDomain` with a hostname in your Cloudflare zone, and add the
   DNS CNAME pointing to `<TUNNEL_UUID>.cfargotunnel.com`.
4. Drop production secrets in `/run` or another runtime path (use sops-nix).

Reference material:

- https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/local-management/
- https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/local-management/ingress/
