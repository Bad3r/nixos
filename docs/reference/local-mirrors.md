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
- **Firefox source docs**: `git-mirror.service` queues
  `git-mirror-firefox-docs.service` after sync when
  `programs.gitMirror.firefoxDocs.enable = true;`

## Enable On Hosts

Common hosts already enable mirrors through `modules/hosts/common/mirrors.nix`:

```nix
localMirrors.enable = true;

home-manager.users.${metaOwner.username}.programs.gitMirror = {
  enable = true;
  firefoxDocs.enable = true;
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
systemctl --user is-enabled git-mirror.timer
systemctl --user status git-mirror.timer --no-pager
systemctl --user start git-mirror.service
systemctl --user list-timers git-mirror.timer
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
Full URLs include a normalized host prefix and strip common host suffixes such as `.org`.

| Repository spec                               | Local path                                          |
| --------------------------------------------- | --------------------------------------------------- |
| `owner/repo`                                  | `$LOCAL_MIRRORS/owner-repo`                         |
| `mdn/content`                                 | `$LOCAL_MIRRORS/mdn-content`                        |
| `mozilla/enterprise-admin-reference`          | `$LOCAL_MIRRORS/mozilla-enterprise-admin-reference` |
| `mozilla-firefox/firefox`                     | `$LOCAL_MIRRORS/mozilla-firefox-firefox`            |
| Firefox built docs                            | `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs`       |
| `mozilla/policy-templates`                    | `$LOCAL_MIRRORS/mozilla-policy-templates`           |
| `openai/codex`                                | `$LOCAL_MIRRORS/openai-codex`                       |
| `https://codeberg.org/librewolf/settings.git` | `$LOCAL_MIRRORS/codeberg-librewolf-settings`        |

## Firefox Source Docs

The Firefox mirror can build source documentation with `./mach doc` after the
mirror updates. Generated docs are intentionally published outside the Firefox
checkout so `git-mirror` can keep the source tree clean.

- Source checkout: `$LOCAL_MIRRORS/mozilla-firefox-firefox`
- Built docs: `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs/current`
- Revision builds: `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs/revisions/<sha>`
- State marker: `$LOCAL_MIRRORS/mozilla-firefox-firefox-docs/last-built-revision`
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

## Adding Repositories

Edit `programs.gitMirror.repos` in `modules/hosts/common/mirrors.nix` for
mirrors that should exist on every managed host:

```nix
programs.gitMirror.repos = [
  "owner/repo"
  "mozilla-firefox/firefox"
  "mdn/content" # https://developer.mozilla.org
  "mozilla/policy-templates"
  "mozilla/enterprise-admin-reference" # Documentation for policy behavior and syntax
  "https://codeberg.org/librewolf/settings.git"
  # ...
];
```

Use a host-specific override only when a mirror should exist on one host but not the other.
