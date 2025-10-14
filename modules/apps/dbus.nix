{
  flake.nixosModules.apps."dbus" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dbus ];
    };
}
