{
  flake.nixosModules.apps."i3lock" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.i3lock ];
    };
}
