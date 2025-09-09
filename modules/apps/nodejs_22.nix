{
  flake.nixosModules.apps.nodejs_22 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_22 ];
    };
}
