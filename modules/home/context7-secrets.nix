{
  flake.homeManagerModules.context7Secrets =
    {
      lib,
      config,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.context7Secrets;
      ctxFile = "${secretsRoot}/context7.yaml";
      ctxFileExists = builtins.pathExists ctxFile;
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      options.home.context7Secrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to provision the optional Home Manager Context7 API key secret.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && ctxFileExists) {
          sops.secrets."context7/api-key" = {
            sopsFile = ctxFile;
            key = "context7_api_key";
            # Use metaOwner instead of config.home.homeDirectory
            path = "${homeDirectory}/.local/share/context7/api-key";
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && !ctxFileExists) {
          warnings = [
            "home.context7Secrets.enable is true but ${ctxFile} is missing; skipping Context7 secret."
          ];
        })
      ];
    };
}
