{
  flake.nixosModules.apps."iproute2" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.iproute2 ];
    };
}
