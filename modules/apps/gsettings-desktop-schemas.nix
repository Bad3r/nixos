{
  flake.nixosModules.apps."gsettings-desktop-schemas" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."gsettings-desktop-schemas" ];
    };
}
