{
  flake.homeManagerModules.cloudflareSecrets =
    {
      lib,
      config,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.cloudflareSecrets;
      secretFile = secretsRoot + "/cloudflare.yaml";
      secretFileExists = builtins.pathExists secretFile;
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      options.home.cloudflareSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to provision the Home Manager Cloudflare API key secret.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && secretFileExists) {
          sops.secrets."cloudflare/api-key" = {
            sopsFile = secretFile;
            key = "CF_MCP_API_KEY";
            # Use metaOwner instead of config.home.homeDirectory
            path = "${homeDirectory}/.local/share/cloudflare/api-key";
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && !secretFileExists) {
          warnings = [
            "home.cloudflareSecrets.enable is true but ${toString secretFile} is missing; skipping Cloudflare secret."
          ];
        })
      ];
    };
}
