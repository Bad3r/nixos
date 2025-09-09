{
  nixpkgs.allowedUnfreePackages = [
    "slack"
  ];

  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        slack
      ];
    };
}
