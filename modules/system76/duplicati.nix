{ inputs, ... }:
let
  manifestFile = inputs.secrets + "/duplicati-config.json";
in
{
  configurations.nixos.system76.module = _: {
    config = {
      services.duplicati-r2 = {
        enable = true; # Secrets available
        configFile = manifestFile;
      };

      # Assertions moved to modules/services/duplicati-r2.nix where the service is defined
    };
  };
}
