{
  flake.nixosModules.apps.nodejs_22 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_22 ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_22 ];
    };
}
