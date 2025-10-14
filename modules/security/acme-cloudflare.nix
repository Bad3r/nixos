_:
let
  acmeModule =
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
in
{
  flake.nixosModules.roles.network.vendor.cloudflare.imports = [ acmeModule ];
}
