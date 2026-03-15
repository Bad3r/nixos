{ secretsRoot, ... }:
{
  # Keep the repository GPG key separate from the base HM stack so hosts opt in
  # explicitly via home-manager.sharedModules.
  flake.homeManagerModules.repoGpg =
    {
      config,
      lib,
      osConfig ? { },
      ...
    }:
    let
      cfg = config.home.repoGpg;
      gpgSecretFile = "${secretsRoot}/gpg/vx.asc";
      gpgSecretExists = builtins.pathExists gpgSecretFile;
      gpgAgentEnabled = lib.attrByPath [ "programs" "gnupg" "agent" "enable" ] false osConfig;
      repoGpgAvailable = cfg.enable && gpgSecretExists;
    in
    {
      options.home.repoGpg = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to provision the repository GPG secret.";
        };

        fingerprint = lib.mkOption {
          type = lib.types.str;
          default = "981DE78A201C2B735FF0B545A3967CCA47D5275F";
          description = "Fingerprint of the repository GPG signing key.";
        };

        secretFile = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = "Absolute path to the repository GPG secret file on disk.";
        };

        secretExists = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether the repository GPG secret file exists on disk.";
        };

        available = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether the repository GPG key is enabled and available for Home Manager.";
        };

        signingReady = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether Git signing should be enabled for the repository GPG key.";
        };
      };

      config = lib.mkMerge [
        {
          home.repoGpg = {
            secretFile = gpgSecretFile;
            secretExists = gpgSecretExists;
            available = repoGpgAvailable;
            signingReady = repoGpgAvailable && gpgAgentEnabled;
          };
        }

        (lib.mkIf repoGpgAvailable {
          sops.secrets."gpg/vx-secret-key" = {
            sopsFile = gpgSecretFile;
            format = "binary";
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && !gpgSecretExists) {
          warnings = [
            "home.repoGpg.enable is true but ${gpgSecretFile} is missing; Git signing will stay disabled."
          ];
        })
      ];
    };
}
