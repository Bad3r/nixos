{
  flake.nixosModules.apps.jnv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jnv ];
    };
}
