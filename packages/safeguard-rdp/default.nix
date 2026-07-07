{
  lib,
  symlinkJoin,
  stdenvNoCC,
  writeShellApplication,
  makeDesktopItem,
  copyDesktopItems,
  remmina,
  coreutils,
}:

let
  version = "0.1.0";

  # rdp:// URI handler for OneIdentity Safeguard "Start RDP Session" launches.
  #
  # Safeguard's SCALUS launch hands the client an rdp:// URI instead of a
  # downloaded .rdp file. The URI payload is NOT Remmina's native
  # rdp://user:pass@host form: it mirrors the .rdp key grammar (full address,
  # username with the account~asset~vaultaddress~token~ blob, remoteapplication*
  # keys, etc). Remmina cannot parse that, so this launcher reconstructs a
  # temporary .rdp from the URI and opens it with the proven Remmina path,
  # removing the manual download/double-click delay that races the one-time
  # launch token. Plain rdp:// URIs are passed straight to Remmina unchanged.
  launcher = writeShellApplication {
    name = "safeguard-rdp-open";

    runtimeInputs = [
      remmina
      coreutils
    ];

    text = # bash
      ''
        raw="''${1:-}"
        if [ -z "$raw" ]; then
          echo "safeguard-rdp-open: missing rdp:// URI argument" >&2
          exit 64
        fi

        # RFC 3986 percent-decode ('+' is treated as space, query-string style).
        # Literal backslashes are doubled first so printf %b keeps them verbatim
        # rather than reading AD names (DOMAIN\user) or \\tsclient paths as escape
        # sequences and corrupting the username or redirection fields.
        urldecode() {
          local s="''${1//\\/\\\\}"
          s="''${s//+/ }"
          printf '%b' "''${s//%/\\x}"
        }

        # Strip scheme, any authority slashes, and a leading '?'.
        body="''${raw#rdp://}"
        body="''${body#/}"
        body="''${body#\?}"
        decoded="$(urldecode "$body")"

        runtime_dir="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}"
        tmp=""
        make_tmp() {
          tmp="$(mktemp "$runtime_dir/safeguard-rdp.XXXXXX.rdp")"
          chmod 600 "$tmp"
        }

        if [[ "$decoded" == *"full address:s:"* ]]; then
          # Inline .rdp content carried verbatim in the URI (line breaks as %0A).
          make_tmp
          printf '%s\n' "$decoded" > "$tmp"
        elif [[ "$body" == *"="* ]]; then
          # Query-parameter form: key=value pairs mirror .rdp keys, and each
          # value keeps its own s:/i: type prefix, e.g.
          #   full%20address=s:10.49.50.124:4489&username=s:account~...
          make_tmp
          IFS='&' read -r -a pairs <<< "$body"
          for pair in "''${pairs[@]}"; do
            [ -n "$pair" ] || continue
            key="$(urldecode "''${pair%%=*}")"
            val="$(urldecode "''${pair#*=}")"
            printf '%s:%s\n' "$key" "$val" >> "$tmp"
          done
        else
          # Plain rdp://user:pass@host:port URI: let Remmina parse it natively.
          exec remmina -c "$raw"
        fi

        if [ ! -s "$tmp" ]; then
          echo "safeguard-rdp-open: could not build a .rdp from URI: $raw" >&2
          rm -f "$tmp"
          exit 65
        fi

        # Safeguard puts the one-time launch token in username and ships no
        # password field, so Remmina would prompt and the token can expire
        # during that prompt: the exact race this launcher removes. Inject the
        # fixed 'sg' placeholder the Safeguard target accepts (matching the
        # 1drdp helper) unless the reconstructed file already carries one.
        if ! grep -qi '^password' "$tmp"; then
          printf 'password:s:sg\n' >> "$tmp"
        fi

        # Open with the proven Remmina path. Remmina may hand the file to an
        # already-running instance and return immediately, so the token-bearing
        # temp file is removed after a grace period rather than synchronously.
        remmina_status=0
        remmina -c "$tmp" || remmina_status=$?
        ( sleep 20; rm -f "$tmp" ) >/dev/null 2>&1 &
        exit "$remmina_status"
      '';
  };

  desktopItem = makeDesktopItem {
    name = "safeguard-rdp";
    desktopName = "Safeguard RDP Launcher";
    genericName = "Remote Desktop";
    comment = "Open OneIdentity Safeguard rdp:// sessions without downloading a file";
    exec = "safeguard-rdp-open %u";
    icon = "remmina";
    categories = [
      "Network"
      "RemoteAccess"
      "Utility"
    ];
    # Handler only; hide from application menus but keep the scheme association.
    noDisplay = true;
    startupNotify = true;
    mimeTypes = [ "x-scheme-handler/rdp" ];
  };

  assets = stdenvNoCC.mkDerivation {
    pname = "safeguard-rdp-assets";
    inherit version;

    dontUnpack = true;

    nativeBuildInputs = [ copyDesktopItems ];

    desktopItems = [ desktopItem ];

    installPhase = ''
      runHook preInstall
      runHook postInstall
    '';
  };

in
symlinkJoin {
  name = "safeguard-rdp-${version}";
  paths = [
    launcher
    assets
  ];

  passthru = {
    inherit
      launcher
      assets
      ;
  };

  meta = {
    description = "OneIdentity Safeguard rdp:// URI handler that launches sessions through Remmina";
    longDescription = ''
      A native handler for the rdp:// URI scheme used by OneIdentity Safeguard's
      "Start RDP Session" (SCALUS) launch, so a privileged session opens the
      instant it is requested instead of after downloading and double-clicking a
      .rdp file. Removing that delay wins the race against Safeguard's
      short-lived one-time launch token, which otherwise expires and the session
      logs off with ERRINFO_LOGOFF_BY_USER.

      The handler reconstructs a temporary .rdp connection file from the URI
      (inline .rdp content or key=value query form) and opens it with Remmina,
      the client already proven to connect through the Safeguard jump host.
      Plain rdp://user:pass@host URIs are forwarded to Remmina unchanged.

      Requires the Safeguard side to be configured for URI launch (the
      "Start RDP Session" button / SCALUS registration); in file-download mode
      Safeguard never emits an rdp:// URI.
    '';
    homepage = "https://github.com/OneIdentity/SCALUS";
    license = lib.licenses.mit;
    mainProgram = "safeguard-rdp-open";
    platforms = lib.platforms.linux;
  };
}
