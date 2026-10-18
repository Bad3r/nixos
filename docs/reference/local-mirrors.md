# Local mirrors

`git-mirror` keeps local clones of upstream repositories for offline reading and source lookups.
Every host on the common baseline turns it on in `modules/hosts/common/mirrors.nix`, which also holds the repository list.

- [Local mirror sync](local-mirrors-sync.md): what a sync does to a mirror, how local work survives it, and the maintenance run.
- [Local mirror docs](local-mirrors-docs.md): the Firefox source docs and Python documentation trees published beside their mirrors.
- [Local mirror troubleshooting](local-mirrors-troubleshooting.md): failed syncs and docs runs, by the line they log.

## Finding a mirror

`$LOCAL_MIRRORS` holds `localMirrors.root`, and `ls $LOCAL_MIRRORS` lists the mirrors a host carries.
Each repository spec lands in one flat directory under the root:

- GitHub shorthand `owner/repo` lands in `owner-repo`, so `NixOS/nixpkgs` is `$LOCAL_MIRRORS/NixOS-nixpkgs`.
- An HTTP(S) URL lands in its host and path joined by dashes, minus `.git`, a leading `www.`, and a `.com`, `.org`, or `.net` suffix.
  `https://codeberg.org/librewolf/settings.git` lands in `$LOCAL_MIRRORS/codeberg-librewolf-settings`.

## Adding a mirror

1. Add the spec to `programs.gitMirror.repos` in `modules/hosts/common/mirrors.nix`.
   A GitHub repository takes the `owner/repo` form even when its source is given as a GitHub URL.

2. Switch the host, from the repository root:

   ```sh
   ./build.sh --host <host>
   ```

3. Start a sync instead of waiting for the timer:

   ```sh
   systemctl --user start git-mirror.service
   ```

The sync logs `<spec>: cloned` in `journalctl --user -u git-mirror.service`, and the directory appears under `$LOCAL_MIRRORS`.
A mirror that only one host needs goes into `programs.gitMirror.repos` in that host's module, which merges with the common list.
Removing a spec stops its sync and leaves its directory in place until it is deleted by hand.

## Mirror root

`modules/hosts/common/mirrors.nix` passes `localMirrors.root` to `programs.gitMirror.root`, so the provisioner and the sync share one path.
`local-mirrors-root.service`, defined in `modules/git/mirror-root.nix`, creates the root as a setgid directory with group `localMirrors.group`.
It then writes the `localMirrors.stampName` stamp into the root.
When a declared mount encloses the root, the unit starts after that mount and skips its run unless the mount is in place.

The sync and both docs services refuse to run without the stamp, so an unmounted volume never gets a stray root on `/`.
A root with no enclosing mount is created unconditionally at boot.
The `local-mirrors-enclosing-mount` flake check tests the enclosing-mount lookup, including roots without one.
