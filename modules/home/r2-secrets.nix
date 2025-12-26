{
  # Home-Manager sops declarations for R2 user env
  #
  # This separate module declares the sops-managed dotenv that is materialized
  # at ~/.config/cloudflare/r2/env (0400). Keep this separate from the base HM
  # module so that home-manager/checks (which load only base/gui) do not fail
  # when sops is not present in the synthetic check environment.
  flake.homeManagerModules.r2Secrets =
    {
      inputs,
      lib,
      metaOwner,
      ...
    }:
    let
      r2Env = inputs.secrets + "/r2.env";
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      config = lib.mkIf (builtins.pathExists r2Env) {
        sops.secrets."cloudflare/r2/env" = {
          sopsFile = r2Env;
          format = "dotenv";
          # Use metaOwner instead of config.home.homeDirectory
          path = "${homeDirectory}/.config/cloudflare/r2/env";
          mode = "0400";
        };
      };
    };
}
