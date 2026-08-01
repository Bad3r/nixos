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
          # Under net.ifnames=0 wlan0 goes to whichever wireless device
          # registers first, so a USB adapter plugged in at boot can take it
          # from the internal card. Pin the card to a name outside the kernel's
          # wlan* namespace so anything keyed to it follows the card. The path
          # is the PCI address encoded in the former name wlp0s20f3, slot 20
          # being 0x14. Confirm at first boot by reading the card's own ID_PATH,
          # which works whether or not the pin took: `udevadm info -q property
          # -p /sys/class/net/wlan0 | grep ID_PATH=`, using wifi0 in the path
          # once the rename applies. A mismatch leaves no device named wifi0,
          # which fails closed. This pin is the only .link udev applies to the
          # card, so it restores the alternative names 99-default.link would
          # otherwise supply, minus its "mac" token: that one derives a
          # wlx<permanent-mac> altname from the factory address, which is the
          # value the "stable" policy exists to stop presenting.
          systemd.network.links."10-wifi0" = {
            matchConfig.Path = "pci-0000:00:14.3";
            linkConfig = {
              Name = "wifi0";
              AlternativeNamesPolicy = "database onboard slot path";
            };
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
