# Secrets Guard

`scripts/lib/secrets-guard.sh` decides whether a `path:` reference may copy a working tree into the world-readable store.
`build.sh` and `scripts/cache-coverage.sh` source it and run it on the two conditions that select `path:`: a linked worktree and `--allow-dirty`.
Both scripts take that selection from `scripts/lib/flake-ref.sh`.
The bare reference fetches through git, which carries only the tracked tree, so it needs no scan.

## Scan

- `path:` copies every untracked path, ignored or not, so the guard scans the whole untracked set rather than the ignored subset.
- The deny list comes from the `# Secrets safety (defense-in-depth)` block of `.gitignore`, and each pattern matches by name against every path component.
- Submodule working trees are scanned with the same patterns, since `path:` copies them whole.
- A pattern the block anchors to a subdirectory still matches by name anywhere, so `git check-ignore` does not confirm every hit.
- An untracked directory that is itself a git repository is a hit on its name alone, since `ls-files` stops at it while `path:` copies it whole.

## Hits

A hit lists the paths and aborts: the guard returns 1, `build.sh` exits 1, and `scripts/cache-coverage.sh` exits 2.
Move the paths outside the worktree, or pass `--allow-secret-copy` (`ALLOW_SECRET_COPY=1`) to copy them anyway.
A primary checkout on the default path evaluates the bare reference, so it copies nothing and has nothing to override.

## Ownership

The secrets block is this repository's convention, so a tree without it has either drifted or never had it.
A tree that tracks `scripts/lib/secrets-guard.sh` and lacks the block has drifted, and the guard aborts.
Any other tree without the block is foreign: the guard prints a notice and skips the scan.
A `.gitignore` that git tracks but the worktree lacks is drift too, while a tree that never had one is skipped.
A directory that is not a git worktree has no ignore set, so it is skipped as well.

## Inoperative Guard

The guard returns 2 when it cannot answer, and both scripts then refuse to continue, saying so.
The causes fall into five groups:

- A tool missing from `PATH`: `git`, `grep`, `awk`, `mktemp`, or `rm`.
  `scripts/cache-coverage.sh` checks `git` and `awk` first and exits 2 with `required tool not found`.
- A temporary file it cannot create, write, or read back, such as on a read-only `TMPDIR` or a full filesystem.
- A `git` call that fails rather than answering: listing untracked files, enumerating submodules, or resolving the worktree root.
  Deciding whether `.gitignore` or `scripts/lib/secrets-guard.sh` is tracked counts too.
- An ignore set it cannot read: a `.gitignore` tracked but absent, or present but unreadable.
  A block that does not yield its required patterns, or an entry that reduces to no name, counts too.
- A directory it cannot take as given: one that does not resolve to an absolute path, or one carrying a `.git` marker git will not open.
  A subdirectory without its own block counts too when its worktree root carries one or drifted from one.

A missing `git` aborts rather than skips, because `--allow-dirty` selects `path:` without consulting git.
An unopenable `.git` aborts for the same reason: a linked worktree that outlived its gitdir still selects `path:` through its `.git` file.
Dubious ownership arrives as an unopenable `.git` on a tree git otherwise reads, so the abort names `safe.directory` beside repairing the repository.

## Unguarded References

The guard covers the reference a script evaluates, not the one that delivered the script.
`nix run path:.#cache-coverage` copies the tree while Lix resolves the installable, before the wrapper starts, so nothing guards that copy.
In a primary checkout the script then keeps the bare reference and scans nothing.
A hand-typed `nix` command on a `path:` reference is unguarded the same way.
Run `scripts/cache-coverage.sh` from the checkout, or `./build.sh --cache-coverage`, when an untracked secret may be present.
