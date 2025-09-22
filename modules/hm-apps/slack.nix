{
  nixpkgs.allowedUnfreePackages = [ "slack" ];

  flake.homeManagerModules.apps.slack =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.slack ];
    };
}
