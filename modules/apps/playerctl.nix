{
  flake.nixosModules.apps.playerctl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.playerctl ];
    };
}
