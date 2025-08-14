{
  nixpkgs.allowedUnfreePackages = [
    "zoom"
  ];

  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        zoom
      ];
    };
}
