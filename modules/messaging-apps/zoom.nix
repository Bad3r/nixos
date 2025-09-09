{
  nixpkgs.allowedUnfreePackages = [
    "zoom"
  ];

  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        zoom
      ];
    };
}
