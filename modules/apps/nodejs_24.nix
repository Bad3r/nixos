{
  flake.nixosModules.apps.nodejs_24 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_24 ];
    };
}
