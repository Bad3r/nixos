/*
  Package: qbittorrent
  Description: Cross-platform BitTorrent client featuring a Qt GUI and embedded web UI.
  Homepage: https://www.qbittorrent.org/
  Documentation: https://github.com/qbittorrent/qBittorrent/wiki
  Repository: https://github.com/qbittorrent/qBittorrent

  Summary:
    * Offers a µTorrent-like interface with RSS, search plugins, sequential downloads, and bandwidth scheduling.
    * Includes a built-in web interface for remote management and supports BitTorrent extensions such as DHT, PEX, and magnet links.
*/
_:
let
  QbittorrentModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.qbittorrent.extended;
    in
    {
      options.programs.qbittorrent.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable qbittorrent.";
        };

        package = lib.mkPackageOption pkgs "qbittorrent" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.qbittorrent = QbittorrentModule;
}
