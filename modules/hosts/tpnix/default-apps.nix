# Per-host default overrides for tpnix.
# Common baselines and the option declaration live in
# modules/hosts/common/default-apps.nix (`host.defaults.*`).
_: {
  configurations.nixos.tpnix.module = {
    host.defaults = {
      audioPlayer = null;
      videoPlayer = null;
    };
  };
}
