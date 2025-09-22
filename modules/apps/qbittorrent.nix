{
  flake.nixosModules.apps.qbittorrent =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.qbittorrent ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.qbittorrent ];
    };
}
