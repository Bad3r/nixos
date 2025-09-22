{
  flake.nixosModules.apps.maim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.maim ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.maim ];
    };
}
