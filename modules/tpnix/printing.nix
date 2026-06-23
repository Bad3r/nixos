{
  config,
  lib,
  secretsRoot,
  ...
}:
let
  printerSecretFile = "${secretsRoot}/tpnix.yaml";
  printerSecretExists = builtins.pathExists printerSecretFile;
  printerSecretName = "tpnix/printing/m604-device-uri";
  printerSecretPath = "/run/secrets/${printerSecretName}";
  printerServiceName = "ensure-tpnix-printer-m604";
  inherit (config.flake.lib.nixos.hosts.tpnix) sopsRuntimeReady;
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
  printerSecretsReady = sopsRuntimeReady && printerSecretExists;
in
{
  configurations.nixos.tpnix.module =
    { config, pkgs, ... }:
    let
      installSecretsDeps = sopsInstallSecretsDeps config;
      stopCups = lib.optionalString (
        config.services.printing.startWhenNeeded && !config.services.printing.stateless
      ) "${pkgs.systemd}/bin/systemctl stop cups.service";
    in
    {
      config = lib.mkMerge [
        (lib.mkIf printerSecretsReady {
          sops.secrets.${printerSecretName} = {
            sopsFile = printerSecretFile;
            format = "yaml";
            key = "m604_device_uri";
            path = printerSecretPath;
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "${printerServiceName}.service" ];
          };

          systemd.services.${printerServiceName} = {
            description = "Ensure tpnix M604 CUPS printer";
            wantedBy = [ "multi-user.target" ];
            wants = [ "cups.service" ];
            after = [ "cups.service" ] ++ installSecretsDeps;
            requires = installSecretsDeps;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              set -euo pipefail

              device_uri="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg printerSecretPath})"
              if [ -z "$device_uri" ]; then
                echo "M604 printer device URI secret is empty" >&2
                exit 1
              fi

              ${pkgs.cups}/bin/lpadmin \
                -p ${lib.escapeShellArg "M604"} \
                -v "$device_uri" \
                -m ${lib.escapeShellArg "gutenprint.5.3://pcl-g_5e/expert"} \
                -D ${lib.escapeShellArg "HP LaserJet M604"} \
                -o ${lib.escapeShellArg "PageSize=A4"} \
                -E
              ${pkgs.cups}/bin/lpadmin -d ${lib.escapeShellArg "M604"}
              ${stopCups}
            '';
          };
        })

        (lib.mkIf (!printerSecretsReady) {
          warnings = [
            "M604 printer queue is disabled on tpnix until SOPS decryption keys are configured."
          ];
        })
      ];
    };
}
