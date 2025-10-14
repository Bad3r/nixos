{
  flake.nixosModules.apps."plocate" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.plocate ];
    };
}
