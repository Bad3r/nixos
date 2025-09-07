{
  nixpkgs.allowedUnfreePackages = [ "protonvpn-gui" ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        protonvpn-gui
        openvpn
        wireguard-tools
      ];

      # Enable necessary services for VPN functionality
      services.resolved.enable = true;
      networking.firewall.checkReversePath = "loose";
    };
}
