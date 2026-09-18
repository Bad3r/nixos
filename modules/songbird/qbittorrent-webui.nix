# The Web UI side of the qBittorrent service in qbittorrent.nix: the desktop
# handler that torrent files and magnet links open in, and the copy of the
# stock Web UI the service serves in place of its built-in one.
_:
let
  # The stock Web UI only lists a #download= link in its Add Torrent Links
  # dialog; this opens the add dialog itself, once the first sync has
  # loaded the categories it offers. The tab exists for those links, so it
  # closes once each add window has come and gone (added, cancelled, or a
  # duplicate); browsers allow that for a tab with one history entry.
  openAddDialogs = ''
    const sources = url.split("\n").map((s) => s.trim()).filter((s) => s.length > 0);
    const pending = new Set(sources.map((source) => "uploadPage-" + encodeURIComponent(source)));
    const seen = new Set();
    const closeWhenDone = () => {
        for (const id of pending) {
            if (document.getElementById(id) !== null)
                seen.add(id);
            else if (seen.has(id))
                pending.delete(id);
        }
        if (pending.size > 0)
            setTimeout(closeWhenDone, 250);
        else
            window.close();
    };
    const openAddDialogs = () => {
        if (syncMainDataLastResponseId === 0) {
            setTimeout(openAddDialogs, 100);
            return;
        }
        for (const source of sources)
            window.qBittorrent.Client.createAddTorrentWindow("QBT_TR(Magnet link)QBT_TR[CONTEXT=DownloadFromURLDialog]", source);
        closeWhenDone();
    };
    openAddDialogs();
  '';

  # The desktop client checks for a duplicate before it shows the add
  # dialog, but here only the dialog learns the info hash, so every add
  # window stays invisible until its own check clears it (data-checked or
  # data-duplicate) or, if no check ever starts for it, for 3 s.
  hideAddWindows = ''
    if (document.getElementById("qbittorrent-webui-hide-style") === null) {
        document.head.append(Object.assign(document.createElement("style"), {
            id: "qbittorrent-webui-hide-style",
            textContent: "div.mocha[id^=uploadPage-]:not([data-checked]), div.mocha[data-duplicate] { opacity: 0 !important; pointer-events: none !important; }"
        }));
    }
    const createAddTorrentWindow = (title, source, metadata = undefined, downloader = undefined) => {
        setTimeout(() => {
            const windowEl = document.getElementById(id);
            if ((windowEl !== null) && !windowEl.hasAttribute("data-duplicate") && !windowEl.hasAttribute("data-checking"))
                windowEl.setAttribute("data-checked", "");
        }, 3000);
  '';

  # The desktop client's duplicate prompt (GUIAddTorrentManager::processTorrent);
  # the stock add dialog closes silently when the server rejects a duplicate.
  promptDuplicate = ''
    const markWindow = (attribute) => window.parent.document.getElementById(windowId)?.setAttribute(attribute, "");
    let duplicateCheck = null;
    const checkDuplicate = async (metadata) => {
        // Marks the window as being checked before the first await, so the
        // 3 s fallback above never reveals it out from under an in-flight
        // check (an unfiltered torrents/info can take longer than that).
        markWindow("data-checking");
        const hashes = [metadata.infohash_v1, metadata.infohash_v2].filter((hash) => hash);
        let existing;
        try {
            // hashes matches TorrentID, which for a v2-only torrent is the
            // v2 infohash truncated to 40 hex chars.
            const response = await fetch("api/v2/torrents/info?hashes=" + [...hashes, ...hashes.map((hash) => hash.slice(0, 40))].join("|"), { cache: "no-store" });
            if (!response.ok)
                throw new Error("torrents/info answered " + response.status);
            existing = (await response.json()).find((torrent) => hashes.includes(torrent.infohash_v1) || hashes.includes(torrent.infohash_v2));
        }
        catch (error) {
            console.error("Duplicate torrent check failed:", error);
            markWindow("data-checked");
            return;
        }
        if (existing === undefined) {
            markWindow("data-checked");
            return;
        }

        markWindow("data-duplicate");
        clearTimeout(loadMetadataTimer);
        loadMetadataTimer = -1;
        // A duplicate magnet's metadata is the existing torrent's, so its
        // trackers come from the link.
        const isMagnet = source.startsWith("magnet:");
        let trackers;
        let webseeds;
        if (isMagnet) {
            const params = [...new URL(source).searchParams];
            trackers = params.filter(([key]) => /^tr(\.\d+)?$/.test(key)).map(([, value]) => value);
            webseeds = params.filter(([key]) => key === "ws").map(([, value]) => value);
        }
        else {
            // addTrackers starts the next tier at each blank line.
            trackers = [...(metadata.trackers ?? [])]
                .sort((a, b) => a.tier - b.tier)
                .flatMap((tracker, i, all) => (((i > 0) && (tracker.tier !== all[i - 1].tier)) ? ["", tracker.url] : [tracker.url]));
            webseeds = metadata.webseeds ?? [];
        }

        const message = "Torrent '" + existing.name + "' is already in the transfer list. ";
        if ((existing.private === true) || (!isMagnet && (metadata.info?.private === true))) {
            alert(message + "Trackers cannot be merged because it is a private torrent.");
        }
        else if (confirm(message + "Do you want to merge trackers from new source?")) {
            try {
                for (const [endpoint, urls] of [["api/v2/torrents/addTrackers", trackers.join("\n")], ["api/v2/torrents/addWebSeeds", webseeds.join("|")]]) {
                    if (urls.length === 0)
                        continue;
                    const response = await fetch(endpoint, { method: "POST", body: new URLSearchParams({ hash: existing.hash, urls: urls }) });
                    if (!response.ok)
                        throw new Error(endpoint + " answered " + response.status + ": " + await response.text());
                }
            }
            catch (error) {
                alert("Could not merge trackers: " + error.message);
            }
        }
        window.parent.qBittorrent.Client.closeFrameWindow(window);
    };
    const populateMetadata = (metadata) => {
        if ((duplicateCheck === null) && (metadata.infohash_v1 || metadata.infohash_v2))
            duplicateCheck = checkDuplicate(metadata).catch((error) => console.error("Duplicate check crashed:", error));
  '';

  # Applies the three patches above to an arbitrary qBittorrent package's own
  # Web UI sources. Parameterized so the perSystem check below can validate
  # them against the pinned package on its own, independent of songbird's
  # config or secrets; extraAttrs lets that check tag the result without
  # songbird's own copy carrying it.
  webuiRootFor =
    {
      pkgs,
      lib,
      qbittorrentPackage,
      extraAttrs ? { },
    }:
    let
      www = "${qbittorrentPackage.src}/src/webui/www";
    in
    pkgs.runCommand "qbittorrent-webui-root-${qbittorrentPackage.version}"
      (
        {
          nativeBuildInputs = [
            pkgs.nodejs-slim
            pkgs.qt6.qttools
          ];
          # Qt warns on every lrelease run under the sandbox's C locale.
          LC_ALL = "C.UTF-8";
        }
        // extraAttrs
      )
      ''
        mkdir -p "$out/translations"
        # Copies, not links: the service refuses a symlinked directory
        # under an alternative root.
        cp -r ${www}/private ${www}/public "$out"
        chmod -R u+w "$out"
        scripts="$out/private/scripts"
        substituteInPlace "$scripts/client.js" \
          --replace-fail 'showDownloadPage([url]);' ${lib.escapeShellArg openAddDialogs} \
          --replace-fail 'const createAddTorrentWindow = (title, source, metadata = undefined, downloader = undefined) => {' ${lib.escapeShellArg hideAddWindows}
        substituteInPlace "$scripts/addtorrent.js" \
          --replace-fail 'const populateMetadata = (metadata) => {' ${lib.escapeShellArg promptDuplicate}
        node --check "$scripts/client.js"
        node --check "$scripts/addtorrent.js"
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
        inherit pkgs lib;
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
          enable = lib.mkOverride 1000 true;
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
  # songbird's secrets; CI evaluates songbird secretless, so lib.mkIf never
  # forces that thunk there and a qBittorrent bump that moves one of the
  # three --replace-fail anchors would otherwise go unnoticed until an
  # actual switch on the host. Build the same patches here against the
  # plain package, independent of secrets or host config.
  perSystem =
    { pkgs, ... }:
    {
      checks."songbird/qbittorrent-webui-root" = webuiRootFor {
        inherit pkgs;
        inherit (pkgs) lib;
        qbittorrentPackage = pkgs.qbittorrent-nox;
        extraAttrs.passthru.runtimeCheck = true;
      };
    };
}
