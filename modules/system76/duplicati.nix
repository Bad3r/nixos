{ inputs, ... }:
let
  credentialsFile = inputs.secrets + "/duplicati-r2.yaml";
  manifestFile = inputs.secrets + "/duplicati-config.json";
in
{
  configurations.nixos.system76.module = _: {
    config = {
      assertions = [
        {
          assertion = builtins.pathExists credentialsFile;
          message = "services.duplicati-r2: missing secrets/duplicati-r2.yaml (encrypt it with sops)";
        }
        {
          assertion = builtins.pathExists manifestFile;
          message = "services.duplicati-r2: missing secrets/duplicati-config.json (encrypt it with sops)";
        }
      ];

      services.duplicati-r2 = {
        enable = true;
        configFile = manifestFile;
      };
    };
  };
}
