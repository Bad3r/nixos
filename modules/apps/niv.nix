{
  flake.modules.nixos.apps.niv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.niv ];
    };
}
