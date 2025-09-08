{
  # Starter Cloudflare Tunnel configuration
  #
  # This enables `services.cloudflared` with a sample, declarative tunnel.
  # Replace placeholders with real values created via `cloudflared tunnel create`.
  #
  # Docs:
  # - Tunnels overview: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
  # - Declarative config: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/local-management/
  # - Ingress rules: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/local-management/ingress/
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    let
      # Replace with your real public hostname under your Cloudflare-managed zone
      # For example, using your zone: "unsigned.sh" → "app.unsigned.sh"
      exampleDomain = "app.unsigned.sh"; # change me
      # Replace with your real Tunnel UUID
      exampleTunnelId = "00000000-0000-0000-0000-000000000000"; # change me

      # A placeholder credentials file stored in the Nix store for evaluation.
      # IMPORTANT: do not put real secrets here. Use a real credentials file
      # produced by `cloudflared tunnel create <name>` then update
      # `credentialsFile` below to point to it (or pass via secrets tooling).
      placeholderCreds = pkgs.writeText "cloudflared-credentials.json" (
        builtins.toJSON {
          AccountTag = "REPLACE_ME";
          TunnelID = exampleTunnelId;
          TunnelSecret = "REPLACE_ME_BASE64";
        }
      );
    in
    {
      services.cloudflared = {
        enable = true;
        # If you have an account cert (from `cloudflared login`), set it here.
        # certificateFile = "/path/to/cert.pem"; # optional, often not needed with credentialsFile per tunnel
        tunnels = {
          "${exampleTunnelId}" = {
            credentialsFile = placeholderCreds;
            ingress = {
              # Route public hostname to a local service
              "${exampleDomain}" = {
                service = "http://127.0.0.1:8080"; # change to your app
              };
            };
            # Fallback when no rules match
            default = "http_status:404";
          };
        };
      };

      # Open note to users at evaluation time (non-fatal)
      assertions = [
        {
          assertion = true;
          message = ''
            Cloudflare Tunnel starter is enabled.
            Next steps:
            1) Create tunnel: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-remote-tunnel/
            2) Replace exampleTunnelId and placeholderCreds with real values
            3) Add DNS CNAME in Cloudflare for app.unsigned.sh → <TUNNEL_UUID>.cfargotunnel.com
               (Team domain like repo.cloudflareaccess.com is for Access SSO pages and policy, not the public hostname)
          '';
        }
      ];
    };
}
