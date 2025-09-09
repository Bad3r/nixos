{
  nixpkgs.allowedUnfreePackages = [ "protonvpn-gui" ];

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.protonvpn-gui ];
    };
}
