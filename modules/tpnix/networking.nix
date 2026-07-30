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
      # this file layers the Wi-Fi name pin and SignalX DNS routing on top.
      config = lib.mkMerge [
        {
          # firewallDnsInterfaces in policy.nix opens UDP 53/67 and TCP 53 for
          # the dnsmasq below. Under net.ifnames=0 a bare wlan0 would go to
          # whichever wireless device registers first, so a USB adapter plugged
          # in at boot could take it; pin the internal card to a name outside
          # the kernel's wlan* namespace instead. The path is the PCI address
          # encoded in the former name wlp0s20f3, slot 20 being 0x14; confirm
          # with `udevadm info -q property -p /sys/class/net/wifi0 | grep
          # ID_PATH=` after the first boot. A mismatch leaves no device named
          # wifi0, so the opening matches nothing rather than the wrong link.
          systemd.network.links."10-wifi0" = {
            matchConfig.Path = "pci-0000:00:14.3";
            linkConfig.Name = "wifi0";
          };
        }

        (lib.mkIf signalxDnsReady {
          environment.etc."NetworkManager/dnsmasq.d/tpnix-signalx.conf".text = ''
            addn-hosts=${signalxSecretPath}
          '';

          networking.networkmanager.dns = "dnsmasq";

          # services.resolved force-sets networking.networkmanager.dns =
          # "systemd-resolved", which conflicts with dnsmasq mode above.
          services.resolved.enable = false;

          sops.secrets.${signalxSecretName} = {
            sopsFile = signalxSecretFile;
            format = "yaml";
            key = "signalx_hosts";
            path = signalxSecretPath;
            owner = "root";
            group = "root";
            mode = "0400";
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
