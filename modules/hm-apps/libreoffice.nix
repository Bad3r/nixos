{
  flake.homeManagerModules.apps.libreoffice =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.libreoffice ];
    };
}
