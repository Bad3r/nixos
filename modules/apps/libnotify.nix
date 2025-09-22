{
  flake.nixosModules.apps.libnotify =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.libnotify ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.libnotify ];
    };
}
