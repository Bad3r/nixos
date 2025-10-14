{
  flake.nixosModules.apps."xrandr" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xrandr" ];
    };
}
