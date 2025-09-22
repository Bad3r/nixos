{
  flake.nixosModules.apps.vlc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vlc ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vlc ];
    };
}
