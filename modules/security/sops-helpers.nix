{ lib, ... }:
{
  flake.lib.security.sopsInstallSecretsDeps =
    nixosConfig: lib.optional nixosConfig.sops.useSystemdActivation "sops-install-secrets.service";
}
