{
  flake.modules.nixos.apps.cmake =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cmake ];
    };
}
