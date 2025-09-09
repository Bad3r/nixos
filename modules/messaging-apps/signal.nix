{
  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        signal-desktop-bin
      ];
    };
}
