{
  config,
  lib,
  secretsRoot,
  ...
}:
let
  signalxSecretFile = secretsRoot + "/tpnix.yaml";
  signalxSecretExists = builtins.pathExists signalxSecretFile;
  signalxSecretName = "tpnix/networking/signalx-hosts";
  signalxSecretPath = "/run/secrets/${signalxSecretName}";
  # NetworkManager spawns dnsmasq without --user (nm-dns-dnsmasq.c), so the
  # privilege-drop identity comes from dnsmasq config. Pinning it here makes
  # the secret's group grant deterministic instead of relying on dnsmasq's
  # compiled-in nobody/dip defaults.
  dnsmasqRuntimeUser = "nm-dnsmasq";
  inherit (config.flake.lib.nixos.hosts.tpnix) sopsRuntimeReady;
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
  signalxDnsReady = sopsRuntimeReady && signalxSecretExists;
in
{
  configurations.nixos.tpnix.module =
    { config, ... }:
    let
      installSecretsDeps = sopsInstallSecretsDeps config;
    in
    {
      # NetworkManager/DHCP base comes from modules/hosts/common/networking.nix;
      # this file layers SignalX DNS routing on top.
      config = lib.mkMerge [
        (lib.mkIf signalxDnsReady {
          environment.etc."NetworkManager/dnsmasq.d/tpnix-signalx.conf".text = ''
            user=${dnsmasqRuntimeUser}
            group=${dnsmasqRuntimeUser}
            addn-hosts=${signalxSecretPath}
          '';

          networking.networkmanager.dns = "dnsmasq";

          users.groups.${dnsmasqRuntimeUser} = { };
          users.users.${dnsmasqRuntimeUser} = {
            isSystemUser = true;
            group = dnsmasqRuntimeUser;
            description = "NetworkManager dnsmasq runtime user";
          };

          # services.resolved force-sets networking.networkmanager.dns =
          # "systemd-resolved", which conflicts with dnsmasq mode above.
          services.resolved.enable = false;

          sops.secrets.${signalxSecretName} = {
            sopsFile = signalxSecretFile;
            format = "yaml";
            key = "signalx_hosts";
            path = signalxSecretPath;
            owner = "root";
            group = dnsmasqRuntimeUser;
            mode = "0440";
            restartUnits = [ "NetworkManager.service" ];
          };

          systemd.services.NetworkManager = {
            after = installSecretsDeps;
            requires = installSecretsDeps;
          };
        })

        (lib.mkIf (!signalxDnsReady) {
          warnings = [
            "SignalX DNS routing is disabled on tpnix until SOPS decryption keys are configured."
          ];
        })
      ];
    };
}
