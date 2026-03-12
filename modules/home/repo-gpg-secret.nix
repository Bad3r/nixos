{ secretsRoot, ... }:
{
  flake.homeManagerModules.repoGpgSecret =
    { lib, ... }:
    let
      gpgSecretFile = "${secretsRoot}/gpg/vx.asc";
      gpgSecretExists = builtins.pathExists gpgSecretFile;
    in
    lib.mkMerge [
      (lib.mkIf gpgSecretExists {
        sops.secrets."gpg/vx-secret-key" = {
          sopsFile = gpgSecretFile;
          format = "binary";
          mode = "0400";
        };
      })
      (lib.mkIf (!gpgSecretExists) {
        warnings = [
          "homeManagerModules.repoGpgSecret is enabled but ${gpgSecretFile} is missing; skipping gpg secret."
        ];
      })
    ];
}
