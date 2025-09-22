{
  flake.homeManagerModules.apps.fd =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.fd ];
    };
}
