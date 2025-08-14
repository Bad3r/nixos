{
  nixpkgs.allowedUnfreePackages = [
    "mattermost-desktop"
  ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mattermost-desktop
      ];
    };
}
