{
  flake.homeManagerModules.googleDeveloperKnowledgeSecrets =
    {
      lib,
      config,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.googleDeveloperKnowledgeSecrets;
      secretFile = secretsRoot + "/google-developer-knowledge-mcp.yaml";
      secretFileExists = builtins.pathExists secretFile;
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      options.home.googleDeveloperKnowledgeSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to provision the Home Manager Google Developer Knowledge MCP API key secret.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && secretFileExists) {
          sops.secrets."google-developer-knowledge/api-key" = {
            sopsFile = secretFile;
            key = "X-Goog-Api-Key";
            # Use metaOwner instead of config.home.homeDirectory
            path = "${homeDirectory}/.local/share/google-developer-knowledge/api-key";
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && !secretFileExists) {
          warnings = [
            "home.googleDeveloperKnowledgeSecrets.enable is true but ${toString secretFile} is missing; skipping Google Developer Knowledge secret."
          ];
        })
      ];
    };
}
