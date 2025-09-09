{
  flake.nixosModules.apps.uv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.uv ];
    };
}
