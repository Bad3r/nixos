{
  flake.homeManagerModules.context7Secrets =
    {
      inputs,
      lib,
      metaOwner,
      ...
    }:
    let
      ctxFile = inputs.secrets + "/context7.yaml";
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      config = lib.mkIf (builtins.pathExists ctxFile) {
        sops.secrets."context7/api-key" = {
          sopsFile = ctxFile;
          key = "context7_api_key";
          # Use metaOwner instead of config.home.homeDirectory
          path = "${homeDirectory}/.local/share/context7/api-key";
          mode = "0400";
        };
      };
    };
}
