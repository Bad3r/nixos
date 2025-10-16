{
  flake.nixosModules.apps."mattermost-desktop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."mattermost-desktop" ];
    };
}
