{
  flake.nixosModules.apps.pamixer =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pamixer ];
    };
}
