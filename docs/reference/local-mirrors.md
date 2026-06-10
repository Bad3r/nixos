# Local Mirrors

Repositories mirrored locally via `git-mirror` for offline access and patching.

## Configuration

The shared mirror list is managed in `modules/hosts/common/mirrors.nix` for
every host that opts into the common host baseline.
The shared mirror root is defined in `modules/git/mirror-root.nix`.
Repositories sync to flat paths under `/data/git`.

- **Host enablement**: Common hosts get `localMirrors.enable = true;` and
  `home-manager.users.${metaOwner.username}.programs.gitMirror.enable = true;`
  from `modules/hosts/common/mirrors.nix`
- **Environment variable**: `$LOCAL_MIRRORS` points to `/data/git`
- **Sync schedule**: Daily via systemd timer
- **Manual sync**: `systemctl --user start git-mirror.service`
- **Sync concurrency**: Common hosts run two repo sync jobs at a time, and
  each repo clone or fetch gets three attempts with backoff before the service
  run fails
- **Firefox source docs**: `git-mirror.service` queues
  `git-mirror-firefox-docs.service` with `OnSuccess=` after sync when
  `programs.gitMirror.firefoxDocs.enable = true;`, so the docs build is not
  part of the mirror sync start transaction
- **Python documentation sources**: `git-mirror.service` queues
  `git-mirror-python-docs.service` with `OnSuccess=` after sync when
  `programs.gitMirror.pythonDocs.enable = true;`. The publisher resolves the
  current stable Python minor version from `https://docs.python.org/3/`, then
  publishes CPython `Doc/` from the matching upstream branch.
- **Switch behavior**: The mirror sync, Firefox docs build, and Python docs
  source publishing services use `X-SwitchMethod=keep-old`; rebuilds update the
  unit files without starting or restarting long-running mirror jobs during Home
  Manager activation
- **Failure recovery**: `git-mirror.service` restarts on failure after 5
  minutes, bounded to three attempts per hour, so transient Git or network
  failures retry without churning forever

## Enable On Hosts

Common hosts already enable mirrors through `modules/hosts/common/mirrors.nix`:

```nix
localMirrors.enable = true;

home-manager.users.${metaOwner.username}.programs.gitMirror = {
  enable = true;
  firefoxDocs.enable = true;
  pythonDocs.enable = true;
  repos = [
    "owner/repo"
    # ...
  ];
};
```

Add shared mirrors to the `repos` list in `modules/hosts/common/mirrors.nix`.
The timer is only created when `programs.gitMirror.enable = true;`.

## Apply And Verify

Rebuild the target host, then verify that the user timer exists and run the first sync manually:

```bash
./build.sh --host <host>
systemctl --user --no-block start git-mirror.service
systemctl --user status git-mirror.timer --no-pager
systemctl --user list-timers git-mirror.timer
systemctl --user is-enabled git-mirror.timer
ls -ld /data/git
```

If the first sync fails, inspect the user service logs:

```bash
journalctl --user -u git-mirror.service -n 50 --no-pager
```

## Path Mapping

`programs.gitMirror.repos` accepts either GitHub `owner/repo` shorthand or
full HTTP(S) Git URLs.
GitHub shorthand keeps the historical `{owner}-{repo}` local path.
Prefer shorthand for GitHub repositories even when the source is given as a
`https://github.com/owner/repo/` URL.
Full URLs include a normalized host prefix and strip common host suffixes such as `.org`.

| Repository spec                                         | Local path                                                 |
| ------------------------------------------------------- | ---------------------------------------------------------- |
| `owner/repo`                                            | `$LOCAL_MIRRORS/owner-repo`                                |
| `NixOS/nix`                                             | `$LOCAL_MIRRORS/NixOS-nix`                                 |
| `NixOS/rfcs`                                            | `$LOCAL_MIRRORS/NixOS-rfcs`                                |
| `DeterminateSystems/nix-installer`                      | `$LOCAL_MIRRORS/DeterminateSystems-nix-installer`          |
| `nix-community/noogle`                                  | `$LOCAL_MIRRORS/nix-community-noogle`                      |
| `mdn/content`                                           | `$LOCAL_MIRRORS/mdn-content`                               |
| `mozilla/enterprise-admin-reference`                    | `$LOCAL_MIRRORS/mozilla-enterprise-admin-reference`        |
| `mozilla-firefox/firefox`                               | `$LOCAL_MIRRORS/mozilla-firefox-firefox`                   |
| Firefox built docs                                      | `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs`              |
| `mozilla/policy-templates`                              | `$LOCAL_MIRRORS/mozilla-policy-templates`                  |
| `mpv-player/mpv`                                        | `$LOCAL_MIRRORS/mpv-player-mpv`                            |
| `openai/codex`                                          | `$LOCAL_MIRRORS/openai-codex`                              |
| `python/cpython`                                        | `$LOCAL_MIRRORS/python-cpython`                            |
| Current stable Python docs source                       | `$LOCAL_MIRRORS/python-cpython-docs/current`               |
| `tridactyl/tridactyl`                                   | `$LOCAL_MIRRORS/tridactyl-tridactyl`                       |
| `https://git.lix.systems/lix-project/lix.git`           | `$LOCAL_MIRRORS/git.lix.systems-lix-project-lix`           |
| `https://git.lix.systems/lix-project/lix-installer.git` | `$LOCAL_MIRRORS/git.lix.systems-lix-project-lix-installer` |
| `https://git.lix.systems/lix-project/nixos-module.git`  | `$LOCAL_MIRRORS/git.lix.systems-lix-project-nixos-module`  |
| `https://codeberg.org/librewolf/settings.git`           | `$LOCAL_MIRRORS/codeberg-librewolf-settings`               |

## Firefox Source Docs

The Firefox mirror can build source documentation with `./mach doc` after the
mirror updates. Generated docs are intentionally published outside the Firefox
checkout so `git-mirror` can keep the source tree clean.

- Source checkout: `$LOCAL_MIRRORS/mozilla-firefox-firefox`
- Built docs: `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs/current`
- Revision builds: `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs/revisions/<sha>`
- State marker: `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs/last-built-revision`
  records the revision plus selected `mach doc` options that affect generated
  output
- Retention: `programs.gitMirror.firefoxDocs.maxRevisions` keeps the newest
  revision and linkcheck output directories, defaulting to `2`

Run or inspect the docs service directly:

```bash
systemctl --user start git-mirror-firefox-docs.service
journalctl --user -u git-mirror-firefox-docs.service -n 100 --no-pager
test -f /data/git/mozilla-firefox-firefox-docs/current/index.html
```

The service skips incomplete mirrors, dirty Firefox checkouts, and revisions
that already have a successful generated docs tree. After publishing a new
`current` symlink, it prunes old revision and linkcheck output directories.

## Python Documentation Sources

The CPython mirror publishes the current stable Python documentation source tree
after the mirror updates. CPython `main` tracks future Python development, so
the publisher does not use the checkout's default branch. It reads
`https://docs.python.org/3/`, extracts the current stable minor branch from the
page title, and archives `Doc/` from `origin/<major.minor>`.

- Source checkout: `$LOCAL_MIRRORS/python-cpython`
- Current stable docs source: `$LOCAL_MIRRORS/python-cpython-docs/current`
- Revision sources:
  `$LOCAL_MIRRORS/python-cpython-docs/revisions/<major.minor>-<sha>/Doc`
- State marker: `$LOCAL_MIRRORS/python-cpython-docs/current-branch` records the
  resolved branch, commit, and version URL
- Retention: `programs.gitMirror.pythonDocs.maxRevisions` keeps the newest
  source revisions, defaulting to `2`

Run or inspect the docs source publisher directly:

```bash
systemctl --user start git-mirror-python-docs.service
journalctl --user -u git-mirror-python-docs.service -n 100 --no-pager
test -f /data/git/python-cpython-docs/current/conf.py
```

When `docs.python.org/3/` reports Python 3.14.x, the published source comes
from CPython branch `3.14`. When the Python project promotes a newer stable
minor version and updates `docs.python.org/3/`, the next successful sync moves
`current` to that branch automatically.

## Adding Repositories

Edit `programs.gitMirror.repos` in `modules/hosts/common/mirrors.nix` for
mirrors that should exist on every managed host:

```nix
programs.gitMirror.repos = [
  "owner/repo"
  "NixOS/nix"
  "NixOS/rfcs"
  "https://git.lix.systems/lix-project/lix.git"
  "https://git.lix.systems/lix-project/lix-installer.git"
  "https://git.lix.systems/lix-project/nixos-module.git"
  "DeterminateSystems/nix-installer"
  "mozilla-firefox/firefox"
  "mdn/content" # https://developer.mozilla.org
  "mozilla/policy-templates"
  "mozilla/enterprise-admin-reference" # Documentation for policy behavior and syntax
  "python/cpython" # Source for docs.python.org
  "tridactyl/tridactyl"
  "https://codeberg.org/librewolf/settings.git"
  # ...
];
```

Use a host-specific override only when a mirror should exist on one host but not the other.
