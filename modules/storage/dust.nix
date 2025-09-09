{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dust ];
    };
}
