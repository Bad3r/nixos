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
      r2Yaml = "${secretsRoot}/r2.yaml";
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      config = lib.mkIf (builtins.pathExists r2Yaml) {
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
      };
    };
}
