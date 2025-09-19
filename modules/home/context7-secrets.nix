{
  flake.homeManagerModules.context7Secrets =
    { lib, ... }:
    let
      ctxFile = ./../../secrets/context7.yaml;
    in
    {
      config = lib.mkIf (builtins.pathExists ctxFile) {
        sops.secrets."context7/api-key" = {
          sopsFile = ctxFile;
          key = "context7_api_key";
          path = "%r/context7/api-key";
          mode = "0400";
        };
      };
    };
}
