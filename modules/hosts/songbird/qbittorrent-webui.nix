# The Web UI side of the qBittorrent service in qbittorrent.nix: the desktop
# handler that torrent files and magnet links open in, and the copy of the
# stock Web UI the service serves in place of its built-in one.
_:
let
  # The package's own Web UI with the scripts in ./qbittorrent-webui added to
  # two of its pages. They reach the stock code only through the exports,
  # window ids, and WebAPI endpoints the perSystem check below asserts, so a
  # qBittorrent bump that rewrites its internals still builds.
  webuiRootFor =
    { pkgs, qbittorrentPackage }:
    let
      www = "${qbittorrentPackage.src}/src/webui/www";
      scripts = ./qbittorrent-webui;
    in
    pkgs.runCommand "qbittorrent-webui-root-${qbittorrentPackage.version}"
      {
        nativeBuildInputs = [
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
      webuiRoot = webuiRootFor {
        inherit pkgs;
        qbittorrentPackage = cfg.package;
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
      root = webuiRootFor {
        inherit pkgs;
        qbittorrentPackage = pkgs.qbittorrent-nox;
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
            touch "$out"
          '';
    };
}
