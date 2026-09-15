/*
  Package: qbittorrent-webui
  Description: Desktop handler for a qBittorrent Web UI that adds torrent files and magnet links through the Web UI API and opens the Web UI in the browser.
  Homepage: https://www.qbittorrent.org/
  Documentation: https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)
  Repository: https://github.com/qbittorrent/qBittorrent

  Summary:
    * Registers `qbittorrent-webui.desktop` for `application/x-bittorrent` and `x-scheme-handler/magnet`, so a browser download or a magnet click lands in a qBittorrent service instead of a desktop client.
    * Posts without a session cookie, so the Web UI has to waive authentication for the address the requests arrive from.

  Options:
    programs.qbittorrent-webui.extended.url: Web UI base URL the handler posts to and opens.

  Example Usage:
    * `qbittorrent-webui` -- Open the Web UI in the default browser.
    * `qbittorrent-webui ~/Downloads/example.torrent` -- Add a torrent file.
    * `qbittorrent-webui 'magnet:?xt=urn:btih:...'` -- Add a magnet link.
*/
_:
let
  QbittorrentWebuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."qbittorrent-webui".extended;

      handler = pkgs.writeShellApplication {
        name = "qbittorrent-webui";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.libnotify
          pkgs.xdg-utils
        ];
        text = ''
          url=${lib.escapeShellArg cfg.url}
          api="$url/api/v2/torrents/add"

          if [ "$#" -eq 0 ]; then
            exec xdg-open "$url"
          fi

          # A launcher-invoked handler has no terminal, so the notification is
          # the only feedback; a missing session bus is logged, not fatal.
          notify() {
            notify-send "$@" || echo "notify-send failed: $*" >&2
          }

          status=0
          for item in "$@"; do
            case "$item" in
              magnet:*)
                if curl -fsS -o /dev/null --data-urlencode "urls=$item" "$api"; then
                  notify "qBittorrent" "Added magnet link"
                else
                  notify -u critical "qBittorrent" "Failed to add magnet link"
                  status=1
                fi
                ;;
              *)
                path=$item
                case "$path" in
                  file://*)
                    path=''${path#file://}
                    path=$(printf '%b' "''${path//%/\\x}")
                    ;;
                esac
                # curl reads "," and ";" in an unquoted -F file name as option
                # separators; its quoted form takes backslash escapes.
                quoted=''${path//\\/\\\\}
                quoted=''${quoted//\"/\\\"}
                if curl -fsS -o /dev/null -F "torrents=@\"$quoted\"" "$api"; then
                  notify "qBittorrent" "Added $(basename "$path")"
                else
                  notify -u critical "qBittorrent" "Failed to add $(basename "$path")"
                  status=1
                fi
                ;;
            esac
          done
          exit "$status"
        '';
      };

      desktopItem = pkgs.makeDesktopItem {
        name = "qbittorrent-webui";
        desktopName = "qBittorrent Web UI";
        genericName = "BitTorrent client";
        comment = "Add torrents to the qBittorrent service and open its Web UI";
        exec = "qbittorrent-webui %U";
        icon = "qbittorrent";
        terminal = false;
        categories = [
          "Network"
          "FileTransfer"
          "P2P"
        ];
        mimeTypes = [
          "application/x-bittorrent"
          "x-scheme-handler/magnet"
        ];
      };

      qbittorrentWebuiPackage = pkgs.symlinkJoin {
        name = "qbittorrent-webui";
        paths = [
          handler
          desktopItem
        ];
      };
    in
    {
      options.programs."qbittorrent-webui".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable qbittorrent-webui.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = qbittorrentWebuiPackage;
          defaultText = lib.literalExpression "generated qbittorrent-webui handler package";
          description = "The qbittorrent-webui package to use.";
        };

        url = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:8080";
          description = "Web UI base URL the handler posts torrents to and opens.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."qbittorrent-webui" = QbittorrentWebuiModule;
}
