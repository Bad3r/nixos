{ lib, secretsRoot, ... }:
let
  manifestFile = "${secretsRoot}/duplicati-config.json";
  credentialsFile = "${secretsRoot}/duplicati-r2.yaml";
  duplicatiSecretsReady = (builtins.pathExists manifestFile) && (builtins.pathExists credentialsFile);
in
{
  configurations.nixos.system76.module = _: {
    config = lib.mkMerge [
      (lib.mkIf duplicatiSecretsReady {
        services.duplicati-r2 = {
          enable = true; # Secrets are handled via sops-nix
          configFile = manifestFile;
        };
      })
      (lib.mkIf (!duplicatiSecretsReady) {
        warnings = [
          "services.duplicati-r2 is disabled because encrypted files are missing: ${manifestFile} and/or ${credentialsFile}. Initialize secrets with `git submodule update --init --recursive` or see docs/sops/README.md."
        ];
      })
    ];
  };
}
