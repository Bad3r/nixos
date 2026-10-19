# ACME Cloudflare DNS-01 Sample

`modules/security/acme-cloudflare-secrets.nix` declares the sops-nix secret
`cf-api-token` and decrypts it to `/run/secrets/cf-api-token` for use by
`security.acme.certs.*.credentialFiles."CF_DNS_API_TOKEN_FILE"`. The repository
keeps no canned ACME certificate configuration, so tailor the `security.acme`
recipe below per host.

```nix
{
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.com";

    certs.${domain} = {
      dnsProvider = "cloudflare";
      credentialFiles."CF_DNS_API_TOKEN_FILE" = "/run/secrets/cf-api-token";
    };
  };
}
```

Implementation notes:

1. Replace `domain` and `defaults.email` with production values.
2. Provide a DNS-edit-scoped Cloudflare API token through
   `modules/security/acme-cloudflare-secrets.nix`: place the token value in
   `secrets/cf-api-token.yaml` under the key `cf_api_token` and encrypt it with
   sops. The module decrypts it to `/run/secrets/cf-api-token`.
3. Ensure the token file contains only the token string--no `KEY=value` prefix.
4. Optionally add `security.acme.certs.<name>.reloadServices` to restart
   dependent daemons after renewals.

Reference material:

- https://search.nixos.org/options?show=security.acme
- https://developers.cloudflare.com/ssl/edge-certificates/challenges/dns-01/
- `nixos_docs_md/222_quick_start.md` (local mirror)
