{
  flake.nixosModules.apps."lvm2" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lvm2 ];
    };
}
