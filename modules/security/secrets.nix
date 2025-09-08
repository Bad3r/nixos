{ inputs, lib, ... }:
{
  flake.modules.nixos.base =
    { config, pkgs, ... }:
    let
      # Detect if act secret file exists to avoid evaluation failures
      actSecretExists = builtins.pathExists (./../../secrets + "/act.yaml");
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      # Place all configuration under the explicit `config` attribute to
      # satisfy strict module syntax checks in flake checks.
      config = {
        environment.systemPackages = with pkgs; [
          age
          sops
        ];

        # Configure sops-nix (key file path can be customized per host)
        sops.age.keyFile = "/var/lib/sops-nix/key.txt";

        # Only declare secrets if the encrypted file is present in repo
        # (prevents evaluation errors when secrets repo is absent)
        _module.args = { };
      }
      // lib.mkIf actSecretExists {
        sops.secrets."act/github_token" = {
          sopsFile = ./../../secrets/act.yaml;
          mode = "0400";
          owner =
            config.users.users.${config.flake.meta.owner.username}.name
              or "${config.flake.meta.owner.username}";
        };

        # Template an env file: GITHUB_TOKEN=...
        sops.templates."act-env" = {
          content = ''
            GITHUB_TOKEN={{ .act/github_token }}
          '';
          mode = "0400";
          owner =
            config.users.users.${config.flake.meta.owner.username}.name
              or "${config.flake.meta.owner.username}";
        };

        # Expose a stable path for act to use
        environment.etc."act/secrets.env".source = config.sops.templates."act-env".path;
      };
    };
}
