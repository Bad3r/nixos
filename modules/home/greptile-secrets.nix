{
  flake.homeManagerModules.greptileSecrets =
    {
      lib,
      config,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.greptileSecrets;
      greptileFile = "${secretsRoot}/greptile.yaml";
      greptileFileExists = builtins.pathExists greptileFile;
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      options.home.greptileSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to provision the Home Manager Greptile API key secret.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && greptileFileExists) {
          sops.secrets."greptile/api-key" = {
            sopsFile = greptileFile;
            key = "greptile_api_key";
            path = "${homeDirectory}/.local/share/greptile/api-key";
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && !greptileFileExists) {
          warnings = [
            "home.greptileSecrets.enable is true but ${greptileFile} is missing; skipping Greptile secret."
          ];
        })
      ];
    };
}
