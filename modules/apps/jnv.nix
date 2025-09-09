{
  flake.modules.nixos.apps.jnv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jnv ];
    };
}
