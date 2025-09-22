{
  nixpkgs.allowedUnfreePackages = [ "zoom" ];

  flake.homeManagerModules.apps.zoom =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.zoom ];
    };
}
