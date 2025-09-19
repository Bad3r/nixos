{
  flake.homeManagerModules.context7Secrets =
    { config, lib, ... }:
    let
      ctxFile = ./../../secrets/context7.yaml;
      keyPath = "${config.home.homeDirectory}/.local/share/context7/api-key";
    in
    {
      config = lib.mkIf (builtins.pathExists ctxFile) {
        sops.secrets."context7/api-key" = {
          sopsFile = ctxFile;
          key = "context7_api_key";
          path = keyPath;
          mode = "0400";
        };
      };
    };
}
