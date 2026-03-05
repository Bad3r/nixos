{ lib, secretsRoot, ... }:
let
  manifestFile = "${secretsRoot}/duplicati-config.json";
  credentialsFile = "${secretsRoot}/duplicati-r2.yaml";
  sopsRuntimeReady = false;
  duplicatiSecretsReady =
    sopsRuntimeReady && (builtins.pathExists manifestFile) && (builtins.pathExists credentialsFile);
in
{
  configurations.nixos.tpnix.module = _: {
    config =
      (lib.optionalAttrs duplicatiSecretsReady {
        services.duplicati-r2 = {
          enable = true; # Secrets are handled via sops-nix
          configFile = manifestFile;
        };
      })
      // (lib.optionalAttrs (!duplicatiSecretsReady) {
        warnings = [
          "services.duplicati-r2 is disabled on tpnix until SOPS decryption keys are configured."
        ];
      });
  };
}
