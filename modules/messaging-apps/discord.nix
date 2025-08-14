{
  nixpkgs.allowedUnfreePackages = [
    "discord"
  ];

  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        discord
      ];
    };
}
