/*
  firefoxpwa: shared site-installer builder

  Every installer that drives `firefoxpwa site install` / `site update` shares
  one hazard: firefoxpwa rewrites the whole of config.json through File::create
  with no lock, so two of them running at once lose one another's sites. Unit
  ordering cannot prevent it. Home Manager activates sd-switch before the
  sops-nix step, so a switch starts one unit and then restarts another through
  PartOf while the first is still installing, which is the direction an After=
  on either unit does not constrain.

  The lock is therefore taken here rather than in each installer: an installer
  that does not take it cannot exist, because this is how they are built.
  Adding another site installer means calling this with its own text, and it
  inherits the lock, the directory it locks in, and the two environment
  variables firefoxpwa resolves its own paths from.

  Callers supply only what is theirs: the site bookkeeping and the entries.
  modules/browsers/firefoxpwa/site-lock-check.nix proves the mutual exclusion,
  against a deliberately unlocked pair that fails the same assertion.
*/
{
  lib,
  writeShellApplication,
  coreutils,
  util-linux,
}:
{
  name,
  dataDir,
  xdgDataHome,
  runtimeInputs ? [ ],
  text,
}:
writeShellApplication {
  inherit name;
  runtimeInputs = runtimeInputs ++ [
    coreutils
    util-linux
  ];
  text = ''
    # Passed in rather than re-derived from XDG_DATA_HOME: callers use this same
    # value for the 0700 activation step and, where a secret backs the site, for
    # the sops secret path. A second rule here would put the records and
    # config.json outside the directory that protects them whenever
    # xdg.dataHome is not at its default.
    data_dir=${lib.escapeShellArg dataDir}
    # Part of the prelude every installer gets, so shellcheck sees it unused in
    # any caller that only needs the directory. Kept here rather than restated
    # per caller: it is the file the lock below exists to protect.
    # shellcheck disable=SC2034
    config_file="$data_dir/config.json"
    # Exported, not just read: firefoxpwa resolves its own userdata tree from
    # FFPWA_USERDATA and, separately, its system-integration directory (the
    # .desktop entry and icon, through directories::BaseDirs) from
    # XDG_DATA_HOME. Neither is read by the scripts themselves, but both are
    # read by every site install / site update they make, so pinning them from
    # the values the caller already chose makes the binary and the script agree
    # by construction rather than through a systemd unit's Environment=.
    export FFPWA_USERDATA="$data_dir"
    export XDG_DATA_HOME=${lib.escapeShellArg xdgDataHome}

    # Created here rather than left to an activation step: the lock below opens
    # a file inside it, and not every caller has something that creates it
    # first. 0700 is what modules/browsers/firefoxpwa/home.nix pins it to.
    install -d -m 700 "$data_dir"

    # Held for the whole run rather than per call: the installs are short, the
    # entries few, and a lock reacquired between them would let another
    # installer land in the gap with a stale copy of config.json.
    exec 9>"$data_dir/.config-lock"
    flock 9

  ''
  + text;
}
