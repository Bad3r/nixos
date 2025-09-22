{
  flake.nixosModules.apps.rofi =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rofi ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rofi ];
    };
}
