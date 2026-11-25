# Shared factory for single-key Home Manager SOPS API key modules.
{
  optionName,
  sopsSecretName,
  sopsFileName,
  sopsKey,
  relativePath,
  description,
  warningLabel,
}:
{
  lib,
  config,
  metaOwner,
  secretsRoot,
  ...
}:
let
  cfg = config.home.${optionName};
  secretFile = secretsRoot + "/${sopsFileName}";
  secretFileExists = builtins.pathExists secretFile;
  homeDirectory = "/home/${metaOwner.username}";
in
{
  options.home.${optionName}.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    inherit description;
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && secretFileExists) {
      sops.secrets.${sopsSecretName} = {
        sopsFile = secretFile;
        key = sopsKey;
        # Use metaOwner instead of config.home.homeDirectory
        path = "${homeDirectory}/.local/share/${relativePath}";
        mode = "0400";
      };
    })

    (lib.mkIf (cfg.enable && !secretFileExists) {
      warnings = [
        "home.${optionName}.enable is true but ${toString secretFile} is missing; skipping ${warningLabel} secret."
      ];
    })
  ];
}
