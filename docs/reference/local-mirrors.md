# Local Mirrors

Repositories mirrored locally via `git-mirror` for offline access and patching.

## Configuration

Mirrors are managed in the host-specific mirror module at `modules/<host>/mirrors.nix`.
The shared mirror root is defined in `modules/git/mirror-root.nix`.
Repositories sync to `/data/git/{owner}-{repo}`.

- **Host enablement**: Set `localMirrors.enable = true;` and `home-manager.users.${metaOwner.username}.programs.gitMirror.enable = true;` in the host mirror module
- **Environment variable**: `$LOCAL_MIRRORS` points to `/data/git`
- **Sync schedule**: Daily via systemd timer
- **Manual sync**: `systemctl --user start git-mirror.service`

## Enable On A Host

Enable mirrors in `modules/<host>/mirrors.nix` by turning on both the shared mirror root and the user sync job:

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

Each host defines its own `programs.gitMirror.repos` list in `modules/<host>/mirrors.nix`.
Each repository spec uses `owner/repo` format and maps to a flat local directory name by replacing `/` with `-`.

| Repository spec | Local path                    |
| --------------- | ----------------------------- |
| `owner/repo`    | `$LOCAL_MIRRORS/owner-repo`   |
| `openai/codex`  | `$LOCAL_MIRRORS/openai-codex` |

## Adding Repositories

Edit `programs.gitMirror.repos` in the relevant `modules/<host>/mirrors.nix` file:

```nix
programs.gitMirror.repos = [
  "owner/repo"
  # ...
];
```
