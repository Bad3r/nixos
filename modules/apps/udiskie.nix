{
  flake.nixosModules.apps.udiskie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.udiskie ];
    };
}
