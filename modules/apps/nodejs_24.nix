{
  flake.nixosModules.apps.nodejs_24 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_24 ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_24 ];
    };
}
