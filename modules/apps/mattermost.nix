{
  nixpkgs.allowedUnfreePackages = [ "mattermost-desktop" ];

  flake.nixosModules.apps.mattermost =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mattermost-desktop ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mattermost-desktop ];
    };
}
