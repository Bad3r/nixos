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
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      environment.systemPackages = with pkgs; [
        age
        sops
      ];

      # Configure sops-nix (key file path can be customized per host)
      sops.age.keyFile = "/var/lib/sops-nix/key.txt";

      # Only declare secrets if the encrypted file is present in repo
      # (prevents evaluation errors when secrets repo is absent)
      _module.args = { };

      # Conditional secrets and templates
      # Use mkMerge to inject conditionally without mixing module syntax
      # Top-level attributes only (no explicit `config = { ... }`).
    }
    // lib.mkIf actSecretExists {
      sops.secrets."act/github_token" = {
        sopsFile = ./../../secrets/act.yaml;
        mode = "0400";
        owner =
          config.users.users.${config.flake.lib.meta.owner.username}.name
            or "${config.flake.lib.meta.owner.username}";
      };

      # Template an env file: GITHUB_TOKEN=...
      sops.templates."act-env" = {
        content = ''
          GITHUB_TOKEN={{ .act/github_token }}
        '';
        mode = "0400";
        owner =
          config.users.users.${config.flake.lib.meta.owner.username}.name
            or "${config.flake.lib.meta.owner.username}";
      };

      # Expose a stable path for act to use
      environment.etc."act/secrets.env".source = config.sops.templates."act-env".path;
    };

}
