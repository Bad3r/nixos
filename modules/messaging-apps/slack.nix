{
  nixpkgs.allowedUnfreePackages = [
    "slack"
  ];

  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        slack
      ];
    };
}
