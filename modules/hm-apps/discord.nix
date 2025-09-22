{
  nixpkgs.allowedUnfreePackages = [ "discord" ];

  flake.homeManagerModules.apps.discord =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.discord ];
    };
}
