{
  flake.modules.nixos.apps.uv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.uv ];
    };
}
