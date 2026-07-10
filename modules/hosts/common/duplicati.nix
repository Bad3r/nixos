# Shared duplicati-r2 wiring. Activates only when the duplicati-r2 module is
# exported, both encrypted payloads exist, and the host registry sets
# sopsRuntimeReady. Hosts opt their owner into read access on the state
# directory with flake.lib.nixos.hosts.<host>.duplicatiStateDirReadable.
{
  config,
  lib,
  metaOwner,
  secretsRoot,
  ...
}:
let
  manifestFile = "${secretsRoot}/duplicati-config.json";
  credentialsFile = "${secretsRoot}/duplicati-r2.yaml";
  duplicatiModuleExists = lib.hasAttrByPath [ "flake" "nixosModules" "duplicati-r2" ] config;
  duplicatiSecretsExist = (builtins.pathExists manifestFile) && (builtins.pathExists credentialsFile);
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  body =
    { hostName, lib, ... }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
      duplicatiReady =
        duplicatiModuleExists && duplicatiSecretsExist && (hostFlags.sopsRuntimeReady or false);
    in
    {
      # services.duplicati-r2 options exist only when the duplicati-r2 module
      # is imported; optionalAttrs keeps the undeclared path untouched.
      config =
        (lib.optionalAttrs duplicatiReady {
          services.duplicati-r2 = {
            enable = true; # Secrets are handled via sops-nix
            configFile = manifestFile;
            stateDirReadableBy = lib.optionals (hostFlags.duplicatiStateDirReadable or false) [
              metaOwner.username
            ];
          };
        })
        // (lib.optionalAttrs (!duplicatiReady) {
          warnings = [
            "services.duplicati-r2 is disabled on ${hostName}: requires flake.lib.nixos.hosts.${hostName}.sopsRuntimeReady = true and encrypted files ${manifestFile} and ${credentialsFile}. Initialize secrets with `git submodule update --init --recursive` or see docs/sops/README.md."
          ];
        });
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
