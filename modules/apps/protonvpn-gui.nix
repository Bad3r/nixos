{
  nixpkgs.allowedUnfreePackages = [ "protonvpn-gui" ];

  flake.modules.nixos.apps.protonvpn-gui =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.protonvpn-gui ];
    };
}
