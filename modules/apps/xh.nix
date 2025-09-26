{
  flake.nixosModules.apps.xh =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xh ];
    };
}
