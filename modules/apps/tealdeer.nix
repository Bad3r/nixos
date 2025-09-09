{
  flake.modules.nixos.apps.tealdeer =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tealdeer ];
    };
}
