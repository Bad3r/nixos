/*
  Package: qbittorrent-webui
  Description: Desktop handler that opens a qBittorrent Web UI and hands it torrent files and magnet links through its add dialog.
  Homepage: https://www.qbittorrent.org/
  Documentation: https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)
  Repository: https://github.com/qbittorrent/qBittorrent

  Summary:
    * Registers `qbittorrent-webui.desktop` for `application/x-bittorrent` and `x-scheme-handler/magnet`, so a browser download or a magnet click opens the Web UI at a `#download=` link, which leads to the add dialog where the category and save path are chosen.
    * Hands over a torrent file as a `file://` URL to a copy in the staging directory, which the qBittorrent service reads itself, so the service must be able to read that directory.

  Options:
    programs.qbittorrent-webui.extended.url: Web UI base URL the handler opens.
    programs.qbittorrent-webui.extended.stagingDir: Directory the handler copies torrent files into for the service to read.

  Example Usage:
    * `qbittorrent-webui` -- Open the Web UI in the default browser.
    * `qbittorrent-webui ~/Downloads/example.torrent` -- Open the add dialog for a torrent file.
    * `qbittorrent-webui 'magnet:?xt=urn:btih:...'` -- Open the add dialog for a magnet link.
*/
_:
let
  # A callPackage function so the check below can build it against stubs.
  qbittorrentWebuiPackage =
    {
      lib,
      writeShellApplication,
      makeDesktopItem,
      symlinkJoin,
      coreutils,
      jq,
      libnotify,
      xdg-utils,
      url,
      stagingDir,
    }:
    let
      handler = writeShellApplication {
        name = "qbittorrent-webui";
        runtimeInputs = [
          coreutils
          jq
          libnotify
          xdg-utils
        ];
        text = ''
          url=${lib.escapeShellArg url}
          staging=${lib.escapeShellArg stagingDir}

          if [ "$#" -eq 0 ]; then
            exec xdg-open "$url"
          fi

          # A launcher-invoked handler has no terminal, so the notification is
          # the only feedback; a missing session bus is logged, not fatal.
          notify() {
            notify-send "$@" || echo "notify-send failed: $*" >&2
          }

          # qBittorrent reads the file itself, so it gets a copy the service can
          # read, under a random name that needs no escaping in a file:// URL.
          stage() {
            local staged
            staged=$(mktemp --tmpdir="$staging" XXXXXXXXXX.torrent) || return 1
            if cp -- "$1" "$staged" && chmod 0640 "$staged"; then
              printf '%s\n' "$staged"
            else
              rm -f -- "$staged"
              return 1
            fi
          }

          sources=()
          status=0
          for item in "$@"; do
            case "$item" in
              magnet:*)
                sources+=("$item")
                ;;
              *)
                path=$item
                case "$path" in
                  file://*)
                    path=''${path#file://}
                    # Backslashes are doubled first so printf %b keeps a
                    # literal backslash in the path instead of reading it as
                    # the start of an escape sequence.
                    path=''${path//\\/\\\\}
                    path=$(printf '%b' "''${path//%/\\x}")
                    ;;
                esac
                if staged=$(stage "$path"); then
                  sources+=("file://$staged")
                else
                  notify -u critical "qBittorrent" "Failed to stage $(basename "$path") in $staging"
                  status=1
                fi
                ;;
            esac
          done

          # The Web UI URI-decodes the fragment and takes one link per line.
          if [ "''${#sources[@]}" -gt 0 ]; then
            xdg-open "$url/#download=$(jq -rn '$ARGS.positional | join("\n") | @uri' --args "''${sources[@]}")"
          fi
          exit "$status"
        '';
      };

      desktopItem = makeDesktopItem {
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
    in
    symlinkJoin {
      name = "qbittorrent-webui";
      paths = [
        handler
        desktopItem
      ];
    };

  QbittorrentWebuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."qbittorrent-webui".extended;
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
          default = pkgs.callPackage qbittorrentWebuiPackage { inherit (cfg) url stagingDir; };
          defaultText = lib.literalExpression "generated qbittorrent-webui handler package";
          description = "The qbittorrent-webui package to use.";
        };

        url = lib.mkOption {
          type = lib.types.str;
          description = "Web UI base URL the handler opens.";
        };

        stagingDir = lib.mkOption {
          type = lib.types.str;
          description = "Directory the handler copies torrent files into; the qBittorrent service reads each copy through a `file://` URL, so it must be able to read this path.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."qbittorrent-webui" = QbittorrentWebuiModule;

  perSystem =
    { pkgs, ... }:
    let
      # Each stub appends its arguments to <name>.log in the working directory,
      # one per line.
      mkStub =
        name:
        pkgs.writeShellApplication {
          inherit name;
          text = ''
            printf '%s\n' "$@" >>${name}.log
          '';
        };
      handler = pkgs.callPackage qbittorrentWebuiPackage {
        xdg-utils = mkStub "xdg-open";
        libnotify = mkStub "notify-send";
        url = "http://webui.invalid:8989";
        # The build sandbox has no fixed writable absolute path; /proc/self/cwd
        # resolves to the directory the handler runs in.
        stagingDir = "/proc/self/cwd/staging";
      };
    in
    {
      # Opts this check into the "Run runtime check suites" step in
      # .github/workflows/check.yml; passthru keeps the flag out of the hash.
      checks."apps/qbittorrent-webui-add-dialog" =
        pkgs.runCommand "qbittorrent-webui-add-dialog-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = with pkgs; [
              coreutils
              diffutils
              gnugrep
              jq
            ];
          }
          ''
            set -o errexit -o nounset -o pipefail
            subject=${handler}/bin/qbittorrent-webui

            mkdir staging
            printf 'd8:announce0:e' >'a b%.torrent'
            magnet='magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=a%26b&tr=udp%3A%2F%2Ft.invalid'

            # A launcher passes a file:// URI, a magnet, and a path that does not
            # exist; the missing one is reported without dropping the others.
            rc=0
            "$subject" "file://$PWD/a%20b%25.torrent" "$magnet" missing.torrent || rc=$?
            if [ "$rc" -ne 1 ]; then
              echo "expected exit 1 for the missing file, got $rc" >&2
              exit 1
            fi
            grep -qxF 'Failed to stage missing.torrent in /proc/self/cwd/staging' notify-send.log

            opened=$(cat xdg-open.log)
            prefix='http://webui.invalid:8989/#download='
            if [ "''${opened#"$prefix"}" = "$opened" ]; then
              echo "the handler opened $opened, not a #download= link" >&2
              exit 1
            fi
            jq -rn --arg fragment "''${opened#"$prefix"}" '$fragment | @urid' >links

            staged=$(head -n 1 links)
            staged=''${staged#file://}
            printf '%s\n' "file://$staged" "$magnet" | diff - links
            cmp 'a b%.torrent' "$staged"
            [ "$(stat -c %a "$staged")" = 640 ]
            copies=(staging/*)
            [ "''${#copies[@]}" = 1 ]

            rm xdg-open.log
            "$subject"
            [ "$(cat xdg-open.log)" = http://webui.invalid:8989 ]
            touch "$out"
          '';
    };
}
