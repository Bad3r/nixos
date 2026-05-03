# Shared gating helper for `sops-install-secrets.service` ordering. The
# unit only exists when `sops.useSystemdActivation = true`; activation-script
# hosts decrypt secrets before any unit ordering. See issue #37.
{ lib, ... }:
let
  sopsInstallSecretsService = "sops-install-secrets.service";
in
{
  flake.lib.security = {
    inherit sopsInstallSecretsService;

    sopsInstallSecretsDeps =
      nixosConfig: lib.optional nixosConfig.sops.useSystemdActivation sopsInstallSecretsService;
  };
}
