{
  flake.nixosModules.apps.vlc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vlc ];
    };
}
