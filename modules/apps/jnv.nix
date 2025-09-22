{
  flake.nixosModules.apps.jnv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jnv ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jnv ];
    };
}
