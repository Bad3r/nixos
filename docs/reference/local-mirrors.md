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

## Enable On Hosts

Common hosts already enable mirrors through `modules/hosts/common/mirrors.nix`:

```nix
localMirrors.enable = true;

home-manager.users.${metaOwner.username}.programs.gitMirror = {
  enable = true;
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

| Repository spec                               | Local path                                   |
| --------------------------------------------- | -------------------------------------------- |
| `owner/repo`                                  | `$LOCAL_MIRRORS/owner-repo`                  |
| `openai/codex`                                | `$LOCAL_MIRRORS/openai-codex`                |
| `https://codeberg.org/librewolf/settings.git` | `$LOCAL_MIRRORS/codeberg-librewolf-settings` |

## Adding Repositories

Edit `programs.gitMirror.repos` in `modules/hosts/common/mirrors.nix` for
mirrors that should exist on every managed host:

```nix
programs.gitMirror.repos = [
  "owner/repo"
  "https://codeberg.org/librewolf/settings.git"
  # ...
];
```

Use a host-specific override only when a mirror should exist on one host but not the other.
