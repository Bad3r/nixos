{
  flake.nixosModules.apps."i3lock-color" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.i3lock-color ];
    };
}
