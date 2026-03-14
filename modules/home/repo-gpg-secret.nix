{ secretsRoot, ... }:
{
  # Keep the repository GPG key separate from the base HM stack so hosts opt in
  # explicitly via home-manager.sharedModules.
  flake.homeManagerModules.repoGpgSecret =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.home.repoGpgSecret;
      gpgSecretFile = "${secretsRoot}/gpg/vx.asc";
      gpgSecretExists = builtins.pathExists gpgSecretFile;
    in
    {
      options.home.repoGpgSecret.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to provision the repository GPG secret.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && gpgSecretExists) {
          sops.secrets."gpg/vx-secret-key" = {
            sopsFile = gpgSecretFile;
            format = "binary";
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && !gpgSecretExists) {
          warnings = [
            "home.repoGpgSecret.enable is true but ${gpgSecretFile} is missing; skipping gpg secret."
          ];
        })
      ];
    };
}
