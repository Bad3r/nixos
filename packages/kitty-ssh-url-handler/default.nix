{
  lib,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  kitty,
  libnotify,
}:

let
  handler = writeShellApplication {
    name = "kitty-ssh-url-handler";
    runtimeInputs = [
      kitty
      libnotify
    ];
    text = ''
      url=''${1:-}

      reject() {
        local reason=$1
        local message=$reason

        if [ -n "$url" ]; then
          message="$reason: $url"
        fi

        printf 'kitty-ssh-url-handler: %s\n' "$message" >&2
        if ! notify-send -u critical "Kitty SSH URL rejected" "$message"; then
          printf 'kitty-ssh-url-handler: notify-send failed while reporting rejection\n' >&2
        fi
        exit 1
      }

      if [ "$#" -ne 1 ]; then
        reject "expected exactly one ssh:// URL argument"
      fi

      case "$url" in
        ssh://*) ;;
        *) reject "not an ssh:// URL" ;;
      esac

      rest=''${url#ssh://}

      # The ssh kitten takes no path argument, so the path stays opaque and is discarded.
      authority=''${rest%%/*}

      # Authority encoding is never decoded because it could smuggle a parser delimiter.
      case "$authority" in
        *%*) reject "percent-encoded authority is rejected" ;;
      esac

      if [ -z "$authority" ]; then
        reject "missing host"
      fi
      case "$authority" in
        *[][]*) reject "bracketed IPv6 literals are not supported" ;;
      esac

      user=""
      have_user=0
      hostport=$authority
      case "$authority" in
        *@*)
          have_user=1
          user=''${authority%%@*}
          hostport=''${authority#*@}
          ;;
      esac

      if [ "$have_user" -eq 1 ] && [ -z "$user" ]; then
        reject "missing user before '@'"
      fi
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

      if [ "$have_user" -eq 1 ]; then
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
      if [ "$have_user" -eq 1 ]; then
        destination="$user@$host"
      fi

      args=(--hold kitten ssh)
      if [ "$have_port" -eq 1 ]; then
        args+=(-p "$port")
      fi
      args+=(-- "$destination")

      exec kitty "''${args[@]}"
    '';
  };

  desktopItem = makeDesktopItem {
    name = "kitty-ssh-url-handler";
    desktopName = "Kitty SSH";
    genericName = "SSH Client";
    comment = "Open ssh:// links in a Kitty window with kitten ssh";
    exec = "${lib.getExe handler} %u";
    icon = "kitty";
    terminal = false;
    noDisplay = true;
    categories = [ "Network" ];
    mimeTypes = [ "x-scheme-handler/ssh" ];
  };
in
symlinkJoin {
  name = "kitty-ssh-url-handler";
  paths = [
    handler
    desktopItem
  ];

  passthru = {
    inherit handler desktopItem;
  };

  meta = {
    description = "Strict ssh:// URL handler for Kitty's SSH kitten";
    homepage = "https://sw.kovidgoyal.net/kitty/kittens/ssh/";
    license = lib.licenses.mit;
    mainProgram = "kitty-ssh-url-handler";
    platforms = lib.platforms.linux;
  };
}
