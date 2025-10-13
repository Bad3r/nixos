{ inputs, lib, ... }:
let
  configPath = inputs.secrets + "/duplicati-config.yaml";
  hasConfig = builtins.pathExists configPath;
in
{
  configurations.nixos.system76.module =
    _:
    lib.mkIf hasConfig {
      config.services.duplicati-r2 = {
        enable = true;
        configFile = configPath;
      };
    };
}
