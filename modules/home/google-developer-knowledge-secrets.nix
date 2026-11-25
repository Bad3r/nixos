{
  flake.homeManagerModules.googleDeveloperKnowledgeSecrets = import ./_mk-sops-api-key-secret.nix {
    optionName = "googleDeveloperKnowledgeSecrets";
    sopsSecretName = "google-developer-knowledge/api-key";
    sopsFileName = "google-developer-knowledge-mcp.yaml";
    sopsKey = "X-Goog-Api-Key";
    relativePath = "google-developer-knowledge/api-key";
    description = "Whether to provision the Home Manager Google Developer Knowledge MCP API key secret.";
    warningLabel = "Google Developer Knowledge";
  };
}
