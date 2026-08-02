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
  signalxConfName = "NetworkManager/dnsmasq.d/tpnix-signalx.conf";
  # NetworkManager spawns dnsmasq without --user (nm-dns-dnsmasq.c), so the
  # privilege-drop identity comes from dnsmasq config. Pinning it here makes
  # the secret's group grant deterministic instead of relying on dnsmasq's
  # compiled-in nobody/dip defaults. Bus-policy neutral: dnsmasq's dbus_init()
  # owns org.freedesktop.NetworkManager.dnsmasq as root before setuid(), so the
  # name stays under NetworkManager's root-scoped policy grant.
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
      signalxSecret = config.sops.secrets.${signalxSecretName};
    in
    {
      # NetworkManager/DHCP base comes from modules/hosts/common/networking.nix;
      # this file layers SignalX DNS routing on top.
      config = lib.mkMerge [
        (lib.mkIf signalxDnsReady {
          environment.etc.${signalxConfName}.text = ''
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
            # sops-nix restartUnits only fires when decrypted secret bytes
            # change, and environment.etc entries are not restart triggers on
            # their own, so a switch that edits the conf snippet alone would
            # leave dnsmasq running under its previous privilege-drop identity.
            # The ownership triple is triggered too: dnsmasq loads addn-hosts
            # only at startup and on SIGHUP, so a permissions-only edit that
            # restores access would otherwise not reach the running process.
            restartTriggers = [
              config.environment.etc.${signalxConfName}.source
              "${signalxSecret.owner}:${signalxSecret.group}:${signalxSecret.mode}"
            ];
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
