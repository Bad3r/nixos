{
  flake.nixosModules.apps.hsetroot =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hsetroot ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hsetroot ];
    };
}
