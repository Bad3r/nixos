{
  nixpkgs.allowedUnfreePackages = [ "protonvpn-gui" ];

  flake.nixosModules.apps."protonvpn-gui" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.protonvpn-gui ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.protonvpn-gui ];
    };
}
