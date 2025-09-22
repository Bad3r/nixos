{
  flake.nixosModules.apps.pandoc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pandoc ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pandoc ];
    };
}
