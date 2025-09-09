{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.duf ];
    };
}
