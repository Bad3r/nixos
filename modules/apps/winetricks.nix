{
  flake.nixosModules.apps."winetricks" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."winetricks" ];
    };
}
