{ inputs, secretsRoot, ... }:
{
  flake.nixosModules.base =
    {
      config,
      pkgs,
      lib,
      metaOwner,
      ...
    }:
    let
      # Detect if act secret file exists to avoid evaluation failures
      actSecretFile = "${secretsRoot}/act.yaml";
      gpgSecretFile = "${secretsRoot}/gpg/vx.asc";
      actSecretExists = builtins.pathExists actSecretFile;
      gpgSecretExists = builtins.pathExists gpgSecretFile;
      ownerName = metaOwner.username;
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      config = {
        environment.systemPackages = with pkgs; [
          age
          sops
        ];

        # Configure sops-nix (key file path can be customized per host)
        sops.age.keyFile = lib.mkForce "/var/lib/sops-nix/key.txt";
        sops.age.sshKeyPaths = lib.mkForce [ ];

        # Only declare secrets if the encrypted file is present in repo
        # (prevents evaluation errors when secrets repo is absent)
        _module.args = { };
      }
      // lib.mkIf actSecretExists {
        sops.secrets."act/github_token" = {
          sopsFile = actSecretFile;
          mode = "0400";
          owner = ownerName;
        };

        # Template an env file: GITHUB_TOKEN=...
        sops.templates."act-env" = {
          content = ''
            GITHUB_TOKEN={{ .act/github_token }}
          '';
          mode = "0400";
          owner = ownerName;
        };

        # Expose a stable path for act to use
        environment.etc."act/secrets.env".source = config.sops.templates."act-env".path;
      }
      // lib.mkIf gpgSecretExists {
        sops.secrets."gpg/vx-secret-key" = {
          sopsFile = gpgSecretFile;
          format = "binary";
          mode = "0400";
          owner = ownerName;
        };
      };
    };

}
