# Local Mirrors

Repositories mirrored locally via `git-mirror` for offline access and patching.

## Configuration

Mirrors are managed declaratively in `modules/system76/mirrors.nix` and synced to `/data/git/{owner}-{repo}`.

- **Environment variable**: `$LOCAL_MIRRORS` points to `/data/git`
- **Sync schedule**: Daily via systemd timer
- **Manual sync**: `systemctl --user start git-mirror.service`

## Mirrored Repositories

| Repository                      | Path                                             | Use When                                            |
| ------------------------------- | ------------------------------------------------ | --------------------------------------------------- |
| NixOS/nixos-hardware            | `$LOCAL_MIRRORS/NixOS-nixos-hardware`            | Hardware profiles or troubleshoot hardware options. |
| NixOS/nixpkgs                   | `$LOCAL_MIRRORS/NixOS-nixpkgs`                   | Vendor patches or inspect upstream expressions.     |
| nix-community/home-manager      | `$LOCAL_MIRRORS/nix-community-home-manager`      | Review module behaviors or backport fixes.          |
| nix-community/nixvim            | `$LOCAL_MIRRORS/nix-community-nixvim`            | Examine NixVim modules and options.                 |
| nix-community/stylix            | `$LOCAL_MIRRORS/nix-community-stylix`            | Inspect Stylix source or apply local patches.       |
| numtide/llm-agents.nix          | `$LOCAL_MIRRORS/numtide-llm-agents.nix`          | LLM agent tooling reference.                        |
| Mic92/sops-nix                  | `$LOCAL_MIRRORS/Mic92-sops-nix`                  | Manage encrypted secrets integrations.              |
| cachix/git-hooks.nix            | `$LOCAL_MIRRORS/cachix-git-hooks.nix`            | Update hook definitions or debug pre-commit.        |
| hercules-ci/flake.parts-website | `$LOCAL_MIRRORS/hercules-ci-flake.parts-website` | Flake-parts documentation and examples.             |
| mightyiam/files                 | `$LOCAL_MIRRORS/mightyiam-files`                 | Modify sources for generated repo artefacts.        |
| numtide/treefmt-nix             | `$LOCAL_MIRRORS/numtide-treefmt-nix`             | Adjust formatting behavior or version pins.         |
| vic/import-tree                 | `$LOCAL_MIRRORS/vic-import-tree`                 | Review import-tree or extend module auto-loading.   |
| github/docs                     | `$LOCAL_MIRRORS/github-docs`                     | GitHub documentation reference.                     |
| i3/i3.github.io                 | `$LOCAL_MIRRORS/i3-i3.github.io`                 | Reference i3 window manager documentation offline.  |
| better-auth/better-auth         | `$LOCAL_MIRRORS/better-auth-better-auth`         | Inspect Better Auth source and patch behavior.      |
| logseq/logseq                   | `$LOCAL_MIRRORS/logseq-logseq`                   | Logseq source and plugin development.               |
| openai/codex                    | `$LOCAL_MIRRORS/openai-codex`                    | Inspect Codex source and integration behavior.      |

## Adding Repositories

Edit `modules/system76/mirrors.nix`:

```nix
programs.gitMirror.repos = [
  "owner/repo"
  # ...
];
```

Rebuild and run `systemctl --user start git-mirror.service`.
