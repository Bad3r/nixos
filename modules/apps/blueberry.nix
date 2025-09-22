{
  flake.nixosModules.apps.blueberry =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.blueberry ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.blueberry ];
    };
}
