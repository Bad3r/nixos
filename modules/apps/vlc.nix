{
  flake.modules.nixos.apps.vlc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vlc ];
    };
}
