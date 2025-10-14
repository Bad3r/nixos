{
  flake.nixosModules.apps."man-db" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."man-db" ];
    };
}
