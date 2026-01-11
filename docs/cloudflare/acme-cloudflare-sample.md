# ACME Cloudflare DNS-01 Sample

The deprecated `modules/security/acme-cloudflare.nix` module enabled a canned
ACME configuration for Cloudflare-managed domains. Instead of wiring it through
the workstation bundle, keep the recipe in docs and tailor it per host.

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
2. Mount a restricted Cloudflare API token (DNS edit scope) at
   `/run/secrets/cf-api-token` or similar using sops-nix.
3. Ensure the token file contains only the token string—no `KEY=value` prefix.
4. Optionally add `security.acme.certs.<name>.reloadServices` to restart
   dependent daemons after renewals.

Reference material:

- https://search.nixos.org/options?show=security.acme
- https://developers.cloudflare.com/ssl/edge-certificates/challenges/dns-01/
- `nixos_docs_md/222_quick_start.md` (local mirror)
