# Logseq Local Workflow

Logseq is managed from the local clone at `/home/vx/git/logseq`. The flake no longer
builds Logseq from source; instead, it wraps the locally built binary in an FHS
environment so it can run anywhere on NixOS.

## Automated Updates

Logseq is refreshed automatically in two places:

1. **System activation** – Every time you rebuild the NixOS configuration the
   activation script runs `logseq-update` as user `vx`. The helper:
   - fetches `origin/master` in `/home/vx/git/logseq`;
   - hard-resets the tree if a new commit is available; and then
   - calls `nix develop .#logseq --accept-flake-config --command ~/dotfiles/.local/bin/sss-update-logseq -f`
     to rebuild the Electron bundle. The resulting binaries land in
     `~/git/logseq/static/out/Logseq-linux-x64/`.

2. **Nightly service** – The user-level timer `logseq-build.timer` (defined by the Logseq app module and enabled through the `productivity` role) fires daily at 03:30 with `Persistent=true`.
   It pulls in `ghq-mirror.service` first so the shared `/git` mirror is
   current, then runs the same Logseq build command. The wrapper script keeps a
   cache in `$XDG_CACHE_HOME/logseq-build/last-built-rev`, so the timer skips the
   rebuild when the current commit matches the last successful build. Force a
   rebuild with `sss-update-logseq -f` if you need to regenerate assets without
   fetching new commits.

If either path fails (for example, while offline) the activation/timer job exits
non-fatally; re-running the build or waiting for the next timer tick will retry.

## Running Logseq

The `logseq` command is provided by the flake and launches the locally built
application inside an FHS user environment with all required Electron runtime
dependencies. Example usage:

```sh
logseq --no-sandbox
```

If the wrapper reports that the Logseq binary is missing, run `logseq-update`
manually or re-run `nixos-rebuild switch` to trigger the activation hook.

## Manual Maintenance

- Repository path: `/home/vx/git/logseq`
- Update script: `~/dotfiles/.local/bin/sss-update-logseq`
- Wrapper: `logseq`
- Manual update: `logseq-update`

You can manually force an update with `logseq-update` if you need to rebuild
outside of a full system rebuild or the nightly timer.
