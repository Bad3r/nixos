{
  flake.nixosModules.apps."ncurses" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ncurses ];
    };
}
