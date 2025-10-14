{
  flake.nixosModules.apps."fuse" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.fuse ];
    };
}
