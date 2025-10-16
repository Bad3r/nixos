{ lib, ... }:
let
  cloudflaredModule =
    { pkgs, ... }:
    let
      exampleDomain = "app.unsigned.sh"; # change me
      exampleTunnelId = "00000000-0000-0000-0000-000000000000"; # change me
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
        tunnels = {
          "${exampleTunnelId}" = {
            credentialsFile = placeholderCreds;
            ingress = {
              "${exampleDomain}" = {
                service = "http://127.0.0.1:8080"; # change to your app
              };
            };
            default = "http_status:404";
          };
        };
      };

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
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "network.vendor.cloudflare";
      modules = [ cloudflaredModule ];
    }
  ];
}
