{
  flake.nixosModules.apps.dmenu =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dmenu ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dmenu ];
    };
}
