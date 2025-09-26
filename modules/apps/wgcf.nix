{
  flake.nixosModules.apps.wgcf =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wgcf ];
    };
}
