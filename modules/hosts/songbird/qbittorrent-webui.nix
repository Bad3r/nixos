# The Web UI side of the qBittorrent service in qbittorrent.nix: the desktop
# handler that torrent files and magnet links open in, and the copy of the
# stock Web UI the service serves in place of its built-in one.
_:
let
  webuiIcons = import ./qbittorrent-webui/_icons.nix;

  # The package's own Web UI with the scripts in ./qbittorrent-webui added to
  # two of its pages. They reach the stock code only through the exports,
  # window ids, and WebAPI endpoints the perSystem check below asserts, so a
  # qBittorrent bump that rewrites its internals still builds.
  # themeCss is appended to the stylesheet every private page loads, icon
  # replaces the favicon, which also heads each dialog, and the stock images
  # in ./qbittorrent-webui/_icons.nix become Octicons in colors.
  webuiRootFor =
    {
      pkgs,
      qbittorrentPackage,
      themeCss,
      icon,
      colors,
    }:
    let
      www = "${qbittorrentPackage.src}/src/webui/www";
      scripts = ./qbittorrent-webui;
      vscode = pkgs.lib.mapAttrs (_: pkgs.lib.removePrefix "#") (
        import ../../stylix/_vscode-dark-2026.nix
      );
      tones = {
        icon = colors.base04; # icon.foreground
        muted = colors.base03;
        error = vscode.errorForeground;
        warning = "cca700"; # notificationsWarningIcon.foreground
        ok = vscode."gitDecoration.addedResourceForeground";
      };
      # An image a bump drops is skipped here and fails the check below.
      replaceImages = pkgs.lib.concatStrings (
        pkgs.lib.mapAttrsToList (name: entry: ''
          if [ -e "$out/private/images/${name}.svg" ]; then
            sed 's|<svg |<svg fill="#${tones.${entry.tone}}" |' \
              ${../../lib/octicons + "/${entry.octicon}-16.svg"} > "$out/private/images/${name}.svg"
          fi
        '') webuiIcons
      );
    in
    pkgs.runCommand "qbittorrent-webui-root-${qbittorrentPackage.version}"
      {
        nativeBuildInputs = [
          pkgs.librsvg
          pkgs.nodejs-slim
          pkgs.qt6.qttools
        ];
        # Qt warns on every lrelease run under the sandbox's C locale.
        LC_ALL = "C.UTF-8";
      }
      ''
        mkdir -p "$out/translations"
        # Copies, not links: the service refuses a symlinked directory
        # under an alternative root.
        cp -r ${www}/private ${www}/public "$out"
        chmod -R u+w "$out"
        cp ${scripts}/index-hooks.js ${scripts}/addtorrent-hooks.js "$out/private/scripts"
        node --check "$out/private/scripts/index-hooks.js"
        node --check "$out/private/scripts/addtorrent-hooks.js"
        # The service fills in CACHEID when it serves each page.
        substituteInPlace "$out/private/index.html" \
          --replace-fail '</head>' '<script defer src="scripts/index-hooks.js?v=''${CACHEID}"></script></head>'
        substituteInPlace "$out/private/addtorrent.html" \
          --replace-fail '</head>' '<script defer src="scripts/addtorrent-hooks.js?v=''${CACHEID}"></script></head>'
        cat ${themeCss} >> "$out/private/css/style.css"
        install -m 444 ${icon} "$out/public/images/qbittorrent-tray.svg"
        rsvg-convert -w 32 -h 32 ${icon} > "$out/public/images/qbittorrent32.png"
        ${replaceImages}
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="20"><path d="M0 0h1v20H0z" fill="#%s"/></svg>' \
          ${colors.base02} > "$out/private/images/toolbox-divider.svg"
        # The flags src/app/CMakeLists.txt builds the built-in copies with.
        for ts in ${www}/translations/*.ts; do
          lrelease -removeidentical -silent "$ts" -qm "$out/translations/$(basename "$ts" .ts).qm"
        done
      '';
in
{
  configurations.nixos.songbird.module =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      cfg = config.services.qbittorrent;
      stagingDir = "/run/qbittorrent-webui-staging";
      themed =
        file: extension:
        config.lib.stylix.colors {
          template = builtins.readFile file;
          inherit extension;
        };
      webuiRoot = webuiRootFor {
        inherit pkgs;
        qbittorrentPackage = cfg.package;
        themeCss = themed ./qbittorrent-webui/theme.css.mustache ".css";
        icon = themed ../../stylix/icons/qbittorrent.svg.mustache ".svg";
        inherit (config.lib.stylix) colors;
      };
    in
    lib.mkMerge [
      (lib.mkIf cfg.enable {
        services.qbittorrent.serverConfig.Preferences.WebUI = {
          AlternativeUIEnabled = true;
          RootFolder = "${webuiRoot}";
        };

        # The handler's copies of opened torrent files, which the service
        # reads through its group; setgid gives each copy that group.
        systemd.tmpfiles.settings."10-qbittorrent-webui-staging".${stagingDir}.d = {
          user = metaOwner.username;
          inherit (cfg) group;
          mode = "2750";
          age = "1d";
        };

        # Only with the service: without it, every magnet click would open a
        # Web UI that was never built. The handler's enable rides along because
        # its url and stagingDir have no default and an enabled handler forces
        # them.
        host.defaults.torrentClient = "qbittorrent-webui";
        programs."qbittorrent-webui".extended = {
          enable = lib.mkOverride 1050 true;
          # The proxy listens on the host under the service's own port.
          url = "http://127.0.0.1:${toString cfg.webuiPort}";
          inherit stagingDir;
        };
      })
      # apps-enable.nix turns the Qt client off, so the common torrentClient
      # default would fail the default-apps assertion here.
      (lib.mkIf (!cfg.enable) { host.defaults.torrentClient = null; })
    ];

  # webuiRoot above is only forced when cfg.enable is true, which needs
  # songbird's secrets, and CI evaluates songbird secretless; this builds the
  # same root against the plain package. The greps fail when a qBittorrent
  # bump drops something the scripts rely on, which on the host only shows as
  # stock behavior plus an error in the browser console.
  perSystem =
    { pkgs, ... }:
    let
      # No Stylix here: the sheet goes in unrendered, and the icon gets a
      # stand-in color so rsvg-convert can draw it.
      root = webuiRootFor {
        inherit pkgs;
        qbittorrentPackage = pkgs.qbittorrent-nox;
        themeCss = ./qbittorrent-webui/theme.css.mustache;
        icon = pkgs.writeText "qbittorrent.svg" (
          builtins.replaceStrings [ "{{base05-hex}}" ] [ "bbbebf" ] (
            builtins.readFile ../../stylix/icons/qbittorrent.svg.mustache
          )
        );
        colors = pkgs.lib.genAttrs [ "base02" "base03" "base04" ] (_: "808080");
      };
      stock = "${pkgs.qbittorrent-nox.src}/src/webui/www/private";
    in
    {
      checks."songbird/qbittorrent-webui-root" =
        pkgs.runCommand "qbittorrent-webui-root-check" { passthru.runtimeCheck = true; }
          ''
            test -e ${root}/private/scripts/index-hooks.js
            expect() {
              grep -qF -- "$2" "${stock}/$1" || { echo "$1 no longer contains: $2" >&2; exit 1; }
            }
            expect scripts/client.js 'createAddTorrentWindow: createAddTorrentWindow'
            expect scripts/client.js 'closeFrameWindow: closeFrameWindow'
            expect scripts/client.js 'categoryMap: categoryMap'
            expect scripts/client.js 'tagMap: tagMap'
            expect scripts/client.js '"api/v2/sync/maindata"'
            expect scripts/client.js 'const id = `''${staticId}-''${encodeURIComponent(source)}`;'
            expect scripts/client.js 'windowId: id'
            expect scripts/client.js '"addtorrent_metadata"'
            expect scripts/addtorrent.js '"api/v2/torrents/fetchMetadata"'
            # The theme overrides these and replaces the favicon in place.
            for var in $(grep -o -- '--color-[a-z-]*:' ${./qbittorrent-webui/theme.css.mustache} | sort -u); do
              expect css/style.css "$var"
            done
            expect index.html 'href="images/qbittorrent-tray.svg"'
            expect index.html 'href="images/qbittorrent32.png"'
            for image in ${pkgs.lib.escapeShellArgs (builtins.attrNames webuiIcons)} toolbox-divider; do
              test -e "${stock}/images/$image.svg" || { echo "images/$image.svg is gone" >&2; exit 1; }
            done
            touch "$out"
          '';
    };
}
