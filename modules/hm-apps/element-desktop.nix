{
  flake.homeManagerModules.apps."element-desktop" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.element-desktop ];
    };
}
