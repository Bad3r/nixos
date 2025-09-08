{ inputs, lib, ... }:
{
  # System-scoped sops-nix declaration for the ACME DNS API token.
  #
  # Decrypts a token into /run/secrets/cf-api-token for use by
  # security.acme.certs.*.credentialFiles."CF_DNS_API_TOKEN_FILE".
  #
  # How to provide the encrypted file:
  # - Create secrets/cf-api-token.yaml with a YAML key `cf_api_token: <value>`
  #   and encrypt it using sops, following docs/sops-nixos.md and
  #   docs/sops-dotfile.example.yaml.
  # - This module guards on the file’s presence to avoid evaluation failures.
  flake.modules.nixos.base =
    { config, ... }:
    let
      cfTokenFile = ./../../secrets/cf-api-token.yaml;
      cfTokenExists = builtins.pathExists cfTokenFile;
    in
    {
      # sops-nix is imported centrally in modules/security/secrets.nix (base),
      # so we only declare the secret here.
      config = lib.mkIf cfTokenExists {
        sops.secrets."cf-api-token" = {
          sopsFile = cfTokenFile;
          key = "cf_api_token"; # read the single YAML key value
          mode = "0400";
          path = "/run/secrets/cf-api-token";
        };
      };
    };
}
