{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      services.tailscale = {
        enable = true;
        useRoutingFeatures = "client";
        openFirewall = true;
      };
      environment.systemPackages = [
        pkgs.tailscale
        pkgs.ktailctl
      ];
      networking.nftables.enable = true;
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
    };
}
