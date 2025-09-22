{
  flake.homeManagerModules.apps."signal-desktop" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.signal-desktop-bin ];
    };
}
