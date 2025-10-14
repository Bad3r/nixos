{
  flake.nixosModules.apps."iotop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.iotop ];
    };
}
