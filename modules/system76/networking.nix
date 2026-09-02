{ config, ... }:
{
  configurations.nixos.system76.module = {
    # No Name=: the kernel's own eth* naming stands under net.ifnames=0, and
    # systemd.link(5) calls a pin into that pool a race. This file exists only
    # to displace 99-default.link, whose AlternativeNamesPolicy carries a "mac"
    # token deriving an enx<permanent-mac> altname from the factory address,
    # which is the value NetworkManager's "stable" policy exists to stop
    # presenting. net.ifnames=0 gates the rename only, not altname generation.
    # NamePolicy is safe to restore here precisely because there is no Name= for
    # it to override; it keeps this adapter on the fleet scheme if
    # networking.usePredictableInterfaceNames is ever flipped.
    systemd.network.links."10-usb-ethernet" = {
      matchConfig.Path = "pci-0000:00:14.0-usb-0:1.4:1.0";
      linkConfig =
        config.flake.lib.nixos._firewallStableNamePolicyLinkConfig
          or (throw "modules/hosts/common/firewall.nix no longer exports flake.lib.nixos._firewallStableNamePolicyLinkConfig");
    };
  };
}
