{
  flake.homeManagerModules.cloudflareSecrets = import ./_mk-sops-api-key-secret.nix {
    optionName = "cloudflareSecrets";
    sopsSecretName = "cloudflare/api-key";
    sopsFileName = "cloudflare.yaml";
    sopsKey = "CF_MCP_API_KEY";
    relativePath = "cloudflare/api-key";
    description = "Whether to provision the Home Manager Cloudflare API key secret.";
    warningLabel = "Cloudflare";
  };
}
