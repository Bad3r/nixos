{ inputs, ... }:
{
  flake.nixosModules.base =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Detect if act secret file exists to avoid evaluation failures
      actSecretExists = builtins.pathExists (./../../secrets + "/act.yaml");
      gpgSecretExists = builtins.pathExists (./../../secrets + "/gpg/vx.asc");
      ownerUsername = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] "vx" config;
      ownerName = lib.attrByPath [ "users" "users" ownerUsername "name" ] ownerUsername config;
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      environment.systemPackages = with pkgs; [
        age
        sops
      ];

      # Configure sops-nix (key file path can be customized per host)
      sops.age = {
        keyFile = "/var/lib/sops-nix/key.txt";
        sshKeyPaths = [ ];
      };

      # Only declare secrets if the encrypted file is present in repo
      # (prevents evaluation errors when secrets repo is absent)
      _module.args = { };

      # Conditional secrets and templates
      # Use mkMerge to inject conditionally without mixing module syntax
      # Top-level attributes only (no explicit `config = { ... }`).
    }
    // lib.mkIf actSecretExists {
      sops.secrets."act/github_token" = {
        sopsFile = inputs.secrets + "/act.yaml";
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
        sopsFile = inputs.secrets + "/gpg/vx.asc";
        format = "binary";
        mode = "0400";
        owner = ownerName;
      };
    };

}
