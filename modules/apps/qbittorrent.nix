/*
  Package: qBittorrent
  Description: Cross-platform BitTorrent client featuring a Qt GUI and embedded web UI.
  Homepage: https://www.qbittorrent.org/
  Documentation: https://github.com/qbittorrent/qBittorrent/wiki
  Repository: https://github.com/qbittorrent/qBittorrent

  Summary:
    * Offers a µTorrent-like interface with RSS, search plugins, sequential downloads, and bandwidth scheduling.
    * Includes a built-in web interface for remote management and supports BitTorrent extensions such as DHT, PEX, and magnet links.

  Options:
    qbittorrent: Launch the Qt GUI client.
    qbittorrent-nox: Run the headless/web UI instance for servers (available in package).
    Preferences: Configure ports, encryption, queue management, and automation scripts.

  Example Usage:
    * `qbittorrent` — Start the GUI to add torrents via magnet links or files.
    * `qbittorrent-nox --webui-port=8080` — Run a web-controlled instance for remote management.
    * Use Tools → RSS Downloader to automate TV show downloads based on filters.
*/

{
  flake.nixosModules.apps.qbittorrent =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.qbittorrent ];
    };

}
