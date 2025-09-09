{
  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        krita
      ];
    };
}
