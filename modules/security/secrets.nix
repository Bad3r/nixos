{ secretsRoot, ... }:
{
  flake.nixosModules.repoSecrets =
    {
      config,
      lib,
      metaOwner,
      ...
    }:
    let
      cfg = config.security.repoSecrets;
      actSecretFile = "${secretsRoot}/act.yaml";
      actSecretExists = builtins.pathExists actSecretFile;
      ownerName = metaOwner.username;
    in
    {
      options.security.repoSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to declare repository-managed system SOPS secrets for act.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && actSecretExists) {
          sops.secrets."act/github_token" = {
            sopsFile = actSecretFile;
            mode = "0400";
            owner = ownerName;
          };

          sops.templates."act-env" = {
            content = ''
              GITHUB_TOKEN={{ .act/github_token }}
            '';
            mode = "0400";
            owner = ownerName;
          };

          environment.etc."act/secrets.env".source = config.sops.templates."act-env".path;
        })

        (lib.mkIf (cfg.enable && !actSecretExists) {
          warnings = [
            "security.repoSecrets.enable is true but ${actSecretFile} is missing; skipping act secret."
          ];
        })
      ];
    };
}
