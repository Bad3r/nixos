{
  flake.nixosModules.apps."modemmanager" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.modemmanager ];
    };
}
