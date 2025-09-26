{
  flake.nixosModules.apps.patch =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.patch ];
    };
}
