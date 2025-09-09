{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hdparm ];
    };
}
