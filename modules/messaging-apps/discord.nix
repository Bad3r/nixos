{
  nixpkgs.allowedUnfreePackages = [
    "discord"
  ];

  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        discord
      ];
    };
}
