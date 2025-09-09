{
  nixpkgs.allowedUnfreePackages = [ "protonvpn-gui" ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.protonvpn-gui ];
    };
}
