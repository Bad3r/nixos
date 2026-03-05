{
  # Home-Manager sops declarations for R2 user env
  #
  # This separate module declares the sops-managed dotenv that is materialized
  # at ~/.config/cloudflare/r2/env (0400). Keep this separate from the base HM
  # module so that home-manager/checks (which load only base/gui) do not fail
  # when sops is not present in the synthetic check environment.
  flake.homeManagerModules.r2Secrets =
    {
      config,
      lib,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.r2Secrets;
      r2Yaml = "${secretsRoot}/r2.yaml";
      r2YamlExists = builtins.pathExists r2Yaml;
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      options.home.r2Secrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to provision Home Manager Cloudflare R2 secrets.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && r2YamlExists) {
          sops = {
            secrets = {
              "cloudflare/r2/account-id" = {
                sopsFile = r2Yaml;
                format = "yaml";
                key = "account_id";
              };

              "cloudflare/r2/access-key-id" = {
                sopsFile = r2Yaml;
                format = "yaml";
                key = "access_key_id";
              };

              "cloudflare/r2/secret-access-key" = {
                sopsFile = r2Yaml;
                format = "yaml";
                key = "secret_access_key";
              };
            };

            templates."cloudflare/r2/env" = {
              content = ''
                R2_ACCOUNT_ID=${config.sops.placeholder."cloudflare/r2/account-id"}
                AWS_ACCESS_KEY_ID=${config.sops.placeholder."cloudflare/r2/access-key-id"}
                AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."cloudflare/r2/secret-access-key"}
              '';
              # Use metaOwner instead of config.home.homeDirectory
              path = "${homeDirectory}/.config/cloudflare/r2/env";
              mode = "0400";
            };
          };
        })

        (lib.mkIf (cfg.enable && !r2YamlExists) {
          warnings = [ "home.r2Secrets.enable is true but ${r2Yaml} is missing; skipping HM R2 secrets." ];
        })
      ];
    };
}
