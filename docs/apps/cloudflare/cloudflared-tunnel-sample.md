# Cloudflare Tunnel Starter Configuration

`modules/apps/cloudflared.nix` installs the `cloudflared` package through
`programs.cloudflared.extended.enable` but wires no tunnel ingress. Keep the
tunnel starter configuration below in documentation and apply it per host
instead of wiring placeholder values automatically.

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
