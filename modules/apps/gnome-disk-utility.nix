{
  flake.nixosModules.apps."gnome-disk-utility" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnome-disk-utility ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnome-disk-utility ];
    };
}
