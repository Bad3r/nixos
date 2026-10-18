# Local mirror troubleshooting

The sync logs one line per spec and step to the user journal, and each docs service logs under its own unit:

```sh
journalctl --user -u git-mirror.service -n 100 --no-pager
```

## `mirror root <root> is absent`

The volume that holds the root is not mounted, and `local-mirrors-root.service` provisions the root only on that volume.

```sh
systemctl status local-mirrors-root.service
```

Mount the volume, then provision the root and sync:

```sh
sudo systemctl start local-mirrors-root.service
systemctl --user start git-mirror.service
```

## `mirror root <root> was not provisioned by local-mirrors-root.service`

The root lacks the stamp that `local-mirrors-root.service` writes, so it sits on the wrong filesystem or was created by hand.

```sh
systemctl status local-mirrors-root.service
```

Mount the volume if it is missing, then provision the root in place and sync:

```sh
sudo systemctl start local-mirrors-root.service
systemctl --user start git-mirror.service
```

## `<spec>: maintenance lock <lock> is held by a running process`

Another `git maintenance run` holds `objects/maintenance.lock` in that mirror.

```sh
fuser -v <lock>
```

Let that process finish or stop it, then start a sync.
A lock that no process holds needs nothing, since the sync removes it.

## `<spec>: maintenance failed`

A maintenance task failed, and git's own error sits just above this line in the journal.
A full or read-only filesystem and a corrupt object store both fail this way.

```sh
git -C "$LOCAL_MIRRORS/<dir>" fsck --connectivity-only
```

Free space or fix permissions; for a corrupt mirror, move its directory out of the root and start a sync, which clones it again.

## `<spec>: clone failed` or `fetch failed` after the retries

The upstream is unreachable, has moved, or asks for credentials, which the sync never answers.

```sh
git ls-remote <url>
```

A network outage clears on a later run; a moved repository needs its new spec in `modules/hosts/common/mirrors.nix`.

## `<spec>: not a git repo`

The mirror path holds a directory without `.git`.
Move it out of the root and start a sync, which clones the spec into the freed path.

## `git-mirror.service` fails with `start-limit-hit`

Repeated failures used up the unit's start limit, so neither a restart nor the timer starts it until the limit interval passes.

```sh
systemctl --user status git-mirror.service
```

Fix the failing spec from its log line, then clear the limit and sync:

```sh
systemctl --user reset-failed git-mirror.service
systemctl --user start git-mirror.service
```

## Published docs stop updating

The docs services start only after a successful sync, so one failing spec freezes `current` in both trees.
Fix the sync, or start a docs service by hand to publish from its mirror as it stands.

## `refusing to build from a dirty Firefox checkout`

The Firefox mirror has local changes, which the next sync stashes and cleans.
Start a sync, which starts the docs service when it succeeds.

## `failed to resolve current stable Python branch`

The `versionUrl` page was unreachable, or its title lacks the `Python 3.<minor> documentation` pattern the publisher parses.

```sh
curl -fsSL https://docs.python.org/3/ | grep -o 'Python 3[.0-9]* [Dd]ocumentation'
```

A fetch failure clears on a later run; a changed title needs the pattern in `modules/hm-apps/_python-docs-publisher.nix` updated.
