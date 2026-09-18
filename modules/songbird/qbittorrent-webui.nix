# The Web UI side of the qBittorrent service in qbittorrent.nix: the desktop
# handler that torrent files and magnet links open in.
_: {
  configurations.nixos.songbird.module =
    {
      config,
      lib,
      metaOwner,
      ...
    }:
    let
      cfg = config.services.qbittorrent;
      stagingDir = "/run/qbittorrent-webui-staging";
    in
    lib.mkMerge [
      (lib.mkIf cfg.enable {
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
}
