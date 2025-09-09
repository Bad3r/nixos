{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnome-disk-utility ];
    };
}
