/*
  Package: kitty-ssh-url-handler
  Description: x-scheme-handler/ssh handler that opens ssh:// links through kitty +kitten ssh.
  Homepage: https://sw.kovidgoyal.net/kitty/kittens/ssh/
  Documentation: https://sw.kovidgoyal.net/kitty/kittens/ssh/

  Summary:
    * Parses an ssh://[user@]host[:port][/path] URL with bash pattern matching only: no shell
      parser, no percent-decoding; a leading '-' on user or host is rejected outright.
    * Execs `kitty +kitten ssh [-p port] -- [user@]host` from an argv array; the path component
      is dropped since the ssh kitten takes none.
    * Registers kitty-ssh-url-handler.desktop as the default x-scheme-handler/ssh application.

  Example Usage:
    * `kitty-ssh-url-handler ssh://user@host:2222/path` -- runs kitty +kitten ssh -p 2222 -- user@host
*/
_: {
  flake.homeManagerModules.apps."kitty-ssh" =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "kitty" "extended" "enable" ] false osConfig;
      kittyPackage = lib.attrByPath [ "programs" "kitty" "extended" "package" ] pkgs.kitty osConfig;

      handler = pkgs.writeShellApplication {
        name = "kitty-ssh-url-handler";
        runtimeInputs = [ kittyPackage ];
        text = ''
          if [ "$#" -ne 1 ]; then
            echo "kitty-ssh-url-handler: expected exactly one ssh:// URL argument" >&2
            exit 1
          fi

          url=$1

          reject() {
            printf 'kitty-ssh-url-handler: %s: %s\n' "$1" "$url" >&2
            exit 1
          }

          case "$url" in
            ssh://*) ;;
            *) reject "not an ssh:// URL" ;;
          esac

          rest=''${url#ssh://}

          # Rejected outright, never decoded: a decoded byte could smuggle '@', ':', '/' past this parser.
          case "$rest" in
            *%*) reject "percent-encoded input is rejected" ;;
          esac

          # The ssh kitten takes no path argument, so only the authority is validated.
          authority=''${rest%%/*}

          if [ -z "$authority" ]; then
            reject "missing host"
          fi
          case "$authority" in
            *[][]*) reject "bracketed IPv6 literals are not supported" ;;
          esac

          user=""
          hostport=$authority
          case "$authority" in
            *@*)
              user=''${authority%%@*}
              hostport=''${authority#*@}
              ;;
          esac

          case "$hostport" in
            *@*) reject "malformed authority" ;;
            *:*:*) reject "malformed host:port" ;;
          esac

          host=$hostport
          port=""
          have_port=0
          case "$hostport" in
            *:*)
              have_port=1
              host=''${hostport%%:*}
              port=''${hostport#*:}
              ;;
          esac

          if [ -z "$host" ]; then
            reject "missing host"
          fi
          case "$host" in
            -*) reject "host must not start with '-'" ;;
            *[!A-Za-z0-9._-]*) reject "host has invalid characters" ;;
          esac

          if [ -n "$user" ]; then
            case "$user" in
              -*) reject "user must not start with '-'" ;;
              *[!A-Za-z0-9._-]*) reject "user has invalid characters" ;;
            esac
          fi

          if [ "$have_port" -eq 1 ]; then
            if [ -z "$port" ]; then
              reject "missing port after ':'"
            fi
            case "$port" in
              0?*) reject "port must not have a leading zero" ;;
              *[!0-9]*) reject "port must be numeric" ;;
              ??????*) reject "port out of range" ;;
            esac
            if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
              reject "port out of range"
            fi
          fi

          destination=$host
          if [ -n "$user" ]; then
            destination="$user@$host"
          fi

          # -- marks the end of kitten options so a validated-but-odd destination can never be read as one.
          args=(+kitten ssh)
          if [ "$have_port" -eq 1 ]; then
            args+=(-p "$port")
          fi
          args+=(-- "$destination")

          exec kitty "''${args[@]}"
        '';
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        home.packages = [ handler ];

        xdg.mimeApps = {
          enable = true;
          defaultApplications."x-scheme-handler/ssh" = "kitty-ssh-url-handler.desktop";
        };

        xdg.desktopEntries."kitty-ssh-url-handler" = {
          name = "Kitty SSH";
          genericName = "SSH Client";
          comment = "Open ssh:// links with kitty +kitten ssh";
          exec = "kitty-ssh-url-handler %u";
          icon = "kitty";
          terminal = false;
          noDisplay = true;
          categories = [ "Network" ];
          mimeType = [ "x-scheme-handler/ssh" ];
        };
      };
    };
}
