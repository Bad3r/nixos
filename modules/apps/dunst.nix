{
  flake.nixosModules.apps.dunst =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dunst ];
    };
}
