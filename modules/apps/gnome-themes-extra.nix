{
  flake.nixosModules.apps."gnome-themes-extra" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."gnome-themes-extra" ];
    };
}
