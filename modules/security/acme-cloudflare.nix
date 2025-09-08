{
  # ACME certificate sample using Cloudflare DNS-01
  #
  # This prepares a certificate via DNS-01 with Cloudflare.
  # Supply an API token via a file mounted at runtime (e.g., /run/secrets/cf-api-token)
  # with permissions restricted to the ACME client.
  #
  # Docs:
  # - NixOS ACME: https://search.nixos.org/options?channel=unstable&show=security.acme
  # - Cloudflare DNS challenge: https://developers.cloudflare.com/ssl/edge-certificates/challenges/dns-01/
  # - Example from local docs: nixos_docs_md/222_quick_start.md
  flake.modules.nixos.workstation =
    _:
    let
      domain = "doh.unsigned.sh"; # change me (your Cloudflare-managed zone)
    in
    {
      security.acme = {
        acceptTerms = true;
        defaults.email = "admin@example.com"; # change me

        certs.${domain} = {
          dnsProvider = "cloudflare";
          # Prefer a restricted-scope token for DNS edit on this zone.
          # The file should contain only the token string (no key=value prefix).
          credentialFiles."CF_DNS_API_TOKEN_FILE" = "/run/secrets/cf-api-token"; # provide at runtime
        };
      };

      assertions = [
        {
          assertion = true;
          message = ''
            ACME Cloudflare DNS-01 sample is configured for doh.example.com.
            Replace the domain, email, and make sure /run/secrets/cf-api-token exists at runtime.
          '';
        }
      ];
    };
}
