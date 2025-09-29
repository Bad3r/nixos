# Logseq Local Workflow

Logseq is managed from the local clone at `/home/vx/git/logseq`. The flake no longer
builds Logseq from source; instead, it wraps the locally built binary in an FHS
environment so it can run anywhere on NixOS.

## Automated Updates

Every time the Nix configuration is rebuilt, the activation script:

1. Fetches `origin/master` in `/home/vx/git/logseq`.
2. If a new commit is available, hard resets the local tree to match upstream.
3. Invokes `nix develop .#logseq --accept-flake-config -c ~/dotfiles/.local/bin/sss-update-logseq -f`
   to rebuild the Electron bundle.
4. The rebuilt application is placed under `~/git/logseq/static/out/Logseq-linux-x64/`.

If the update step fails (for example, due to working offline) the activation
script exits without aborting the rebuild. Re-running the rebuild will retry the
update.

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
outside of a full system rebuild.
