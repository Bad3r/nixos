{
  flake.nixosModules.apps."imagemagick" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.imagemagick ];
    };
}
