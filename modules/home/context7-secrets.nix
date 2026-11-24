{
  flake.homeManagerModules.context7Secrets = import ./_mk-sops-api-key-secret.nix {
    optionName = "context7Secrets";
    sopsSecretName = "context7/api-key";
    sopsFileName = "context7.yaml";
    sopsKey = "context7_api_key";
    relativePath = "context7/api-key";
    description = "Whether to provision the optional Home Manager Context7 API key secret.";
    warningLabel = "Context7";
  };
}
