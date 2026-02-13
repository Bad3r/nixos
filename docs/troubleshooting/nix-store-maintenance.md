# Nix Store Maintenance

This runbook defines the default repair workflow for this host.

## Host Defaults

Configured automation and store behavior:

- `modules/system76/nh.nix`
  - `programs.nh.clean.enable = true`
  - `programs.nh.clean.dates = "weekly"`
  - `programs.nh.clean.extraArgs = "--keep-since 14d --keep 3"`
- `modules/system76/nix-settings.nix`
  - `nix.settings.auto-optimise-store = true`

Because `auto-optimise-store` is enabled globally, this workflow does not include a separate `nix store optimise` step.

## Primary Workflow (`sss-nix-repair`)

Use the custom package command:

```sh
sss-nix-repair
```

What it does:

1. Runs `nh clean all --keep-since 14d --keep 3`
2. Runs `sudo nix store verify --all --repair --no-trust`
3. Maps corrupted paths to user/system generations
4. Lists all user/system generations
5. Prompts before deleting non-current corrupted generations
6. Runs `sudo nix store gc` when deletions were performed

### Common Flags

```sh
sss-nix-repair --dry-run
sss-nix-repair --yes
sss-nix-repair --keep-since 30d --keep 5
sss-nix-repair --trust
sss-nix-repair --no-clean --no-verify
```

## Manual Fallback Commands

If the helper command is unavailable, use:

```sh
nh clean all --keep-since 14d --keep 3
sudo nix store verify --all --repair --no-trust
```

Then inspect roots for any reported corrupted path and handle impacted generations manually:

```sh
nix-store -q --roots /nix/store/<path>
nix-env -p ~/.local/state/nix/profiles/profile --list-generations
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
```
