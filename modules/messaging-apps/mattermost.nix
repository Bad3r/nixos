{
  nixpkgs.allowedUnfreePackages = [
    "mattermost-desktop"
  ];

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mattermost-desktop
      ];
    };
}
