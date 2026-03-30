{ lib, pkgs }:
let
  execPolicyRule =
    {
      pattern,
      decision ? "allow",
      justification ? null,
    }:
    let
      justificationPart = lib.optionalString (
        justification != null
      ) ", justification=${builtins.toJSON justification}";
    in
    "prefix_rule(pattern=${builtins.toJSON pattern}, decision=${builtins.toJSON decision}${justificationPart})";

  execPolicyHostExecutable =
    {
      name,
      paths,
    }:
    "host_executable(name=${builtins.toJSON name}, paths=${builtins.toJSON paths})";

  # Translate common rm flags into rip so Codex defaults to recoverable deletions.
  rmShim = pkgs.writeShellScriptBin "rm" ''
    set -euo pipefail

    force=0
    operands=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --)
          shift
          while [ "$#" -gt 0 ]; do
            operands+=("$1")
            shift
          done
          break
          ;;
        -f|--force)
          force=1
          shift
          ;;
        -r|-R|--recursive)
          shift
          ;;
        -[!-]*)
          bundle="''${1#-}"
          unsupported="''${bundle//[fRr]/}"
          if [ -n "$unsupported" ]; then
            echo "rm shim: unsupported rm option '$1'; use rip directly for nonstandard flags" >&2
            exit 2
          fi
          case "$bundle" in
            *f*)
              force=1
              ;;
          esac
          shift
          ;;
        --*)
          echo "rm shim: unsupported rm option '$1'; use rip directly for nonstandard flags" >&2
          exit 2
          ;;
        *)
          operands+=("$1")
          shift
          ;;
      esac
    done

    cmd=(${lib.getExe pkgs.rip2})
    if [ "$force" -eq 1 ]; then
      cmd+=(--force)
    fi

    if [ "''${#operands[@]}" -eq 0 ]; then
      exec "''${cmd[@]}"
    fi

    exec "''${cmd[@]}" -- "''${operands[@]}"
  '';

  # Scope recoverable bare `rm` rewrites to the top-level Codex shell command
  # instead of mutating PATH for every subprocess those commands spawn.
  #
  # Keep the wrapper executable named `zsh` so Codex continues to classify
  # `zsh -lc ...` invocations as shell commands and applies execpolicy to the
  # inner script instead of requiring a blanket allowlist for the wrapper.
  codexZshWrapper = pkgs.writeShellScriptBin "zsh" ''
    set -euo pipefail

    realZsh=${lib.getExe pkgs.zsh}
    rmShimPath=${rmShim}/bin/rm

    if [ "$#" -ge 2 ] && { [ "$1" = "-c" ] || [ "$1" = "-lc" ]; }; then
      shellFlag="$1"
      wrappedCommand="$2"
      shift 2

      export CODEX_WRAPPED_COMMAND="$wrappedCommand"
      exec "$realZsh" "$shellFlag" '
        rm() {
          "'"$rmShimPath"'" "$@"
        }
        eval "$CODEX_WRAPPED_COMMAND"
      ' "$@"
    fi

    exec "$realZsh" "$@"
  '';

  execPolicyManagedRules =
    let
      allowAllCommands = [
        "rip"
        "sed"
        "head"
        "tail"
        "awk"
        "nl"
        "rg"
        "mktemp"
        "codex"
        "claude"
        "grep"
        "jq"
        "yq"
        "htmlq"
        "sqlite"
        "sqlite3"
        "cat"
        "stat"
        "uv"
        "bun"
        "npm"
        "npx"
        "bunx"
        "deno"
        "devenv"
        "direnv"
        "treefmt"
        "touch"
        "ls"
        "exa"
        "eza"
        "du"
        "lsblk"
        "playwright"
        "chromium"
      ];

      allowedNixPatterns = [
        [
          "nix"
          "develop"
        ]
        [
          "nix"
          "run"
        ]
        [
          "nix"
          "shell"
        ]
        [
          "nix"
          "fmt"
        ]
        [
          "nix"
          "eval"
        ]
        [
          "nix"
          "build"
        ]
        [
          "nix"
          "flake"
          "check"
        ]
        [
          "nix"
          "store"
          "diff-closure"
        ]
        [
          "nix"
          "store"
          "repair"
        ]
        [ "nix-instantiate" ]
      ];

      promptedGitRules = [
        {
          pattern = [
            "git"
            "clean"
          ];
          decision = "prompt";
          justification = "Potentially destructive git command; ask before running.";
        }
        {
          pattern = [
            "git"
            "reset"
          ];
          decision = "prompt";
          justification = "Potentially destructive git command; ask before running.";
        }
        {
          pattern = [
            "git"
            "rebase"
          ];
          decision = "prompt";
          justification = "History-rewriting git command; ask before running.";
        }
        {
          pattern = [
            "git"
            "restore"
          ];
          decision = "prompt";
          justification = "This can discard tracked changes; ask before running.";
        }
        {
          pattern = [
            "git"
            "stash"
            "drop"
          ];
          decision = "prompt";
          justification = "Dropping a stash is destructive; ask before running.";
        }
        {
          pattern = [
            "git"
            "stash"
            "clear"
          ];
          decision = "prompt";
          justification = "Clearing stashes is destructive; ask before running.";
        }
        {
          pattern = [
            "git"
            "stash"
            "pop"
          ];
          decision = "prompt";
          justification = "Popping a stash mutates the worktree; ask before running.";
        }
        {
          pattern = [
            "git"
            "branch"
            "-d"
          ];
          decision = "prompt";
          justification = "Branch deletion should ask before running.";
        }
        {
          pattern = [
            "git"
            "branch"
            "-D"
          ];
          decision = "prompt";
          justification = "Force branch deletion should ask before running.";
        }
        {
          pattern = [
            "git"
            "branch"
            "--delete"
          ];
          decision = "prompt";
          justification = "Branch deletion should ask before running.";
        }
        {
          pattern = [
            "git"
            "tag"
            "-d"
          ];
          decision = "prompt";
          justification = "Tag deletion should ask before running.";
        }
        {
          pattern = [
            "git"
            "tag"
            "--delete"
          ];
          decision = "prompt";
          justification = "Tag deletion should ask before running.";
        }
        {
          pattern = [
            "git"
            "worktree"
            "remove"
          ];
          decision = "prompt";
          justification = "Removing a worktree can delete files; ask before running.";
        }
        {
          pattern = [
            "git"
            "remote"
            "prune"
          ];
          decision = "prompt";
          justification = "Remote prune deletes remote-tracking refs; ask before running.";
        }
        {
          pattern = [
            "git"
            "filter-branch"
          ];
          decision = "prompt";
          justification = "History-rewriting git command; ask before running.";
        }
        {
          pattern = [
            "git"
            "filter-repo"
          ];
          decision = "prompt";
          justification = "History-rewriting git command; ask before running.";
        }
        {
          pattern = [
            "git"
            "gc"
          ];
          decision = "prompt";
          justification = "Garbage collection can make history harder to recover; ask before running.";
        }
        {
          pattern = [
            "git"
            "prune"
          ];
          decision = "prompt";
          justification = "Pruning unreachable objects should ask before running.";
        }
        {
          pattern = [
            "git"
            "reflog"
            "expire"
          ];
          decision = "prompt";
          justification = "Expiring reflog entries reduces recovery options; ask before running.";
        }
        {
          pattern = [
            "git"
            "push"
            "-f"
          ];
          decision = "prompt";
          justification = "Force push should ask before running.";
        }
        {
          pattern = [
            "git"
            "push"
            "--force"
          ];
          decision = "prompt";
          justification = "Force push should ask before running.";
        }
        {
          pattern = [
            "git"
            "push"
            "--force-with-lease"
          ];
          decision = "prompt";
          justification = "Force push should ask before running.";
        }
        {
          pattern = [
            "git"
            "push"
            "--mirror"
          ];
          decision = "prompt";
          justification = "Mirroring a push can rewrite or delete many remote refs; ask before running.";
        }
        {
          pattern = [
            "git"
            "push"
            "--delete"
          ];
          decision = "prompt";
          justification = "Deleting remote refs should ask before running.";
        }
        {
          pattern = [
            "git"
            "push"
            "--prune"
          ];
          decision = "prompt";
          justification = "Pruning remote refs should ask before running.";
        }
      ];

      forbiddenRmRules = [
        {
          pattern = [ "/bin/rm" ];
          decision = "forbidden";
          justification = "Use `rm` (shimmed to `rip`) or `rip` directly.";
        }
        {
          pattern = [ "/usr/bin/rm" ];
          decision = "forbidden";
          justification = "Use `rm` (shimmed to `rip`) or `rip` directly.";
        }
        {
          pattern = [ "/run/current-system/sw/bin/rm" ];
          decision = "forbidden";
          justification = "Use `rm` (shimmed to `rip`) or `rip` directly.";
        }
      ];
    in
    lib.concatStringsSep "\n" (
      [
        "# Managed by Home Manager. Edit modules/agents/codex/_exec-policy.nix."
        "# Allowlisted nix commands bypass sandbox because Linux Codex currently cannot use"
        "# network.allow_unix_sockets to reach /nix/var/nix/daemon-socket/socket."
        "# Git destructive coverage is best-effort: execpolicy only matches argv prefixes,"
        "# so forms like `git -C repo reset --hard`, `git checkout -- path`, or"
        "# `git push origin main --force` do not hit these prompt rules."
        ""
        "# Bare rm resolves to a local shim that runs rip. Common absolute rm paths are forbidden."
        (execPolicyHostExecutable {
          name = "rm";
          paths = [ "${rmShim}/bin/rm" ];
        })
        (execPolicyRule {
          pattern = [ "rm" ];
          decision = "allow";
          justification = "Bare `rm` is rewritten to the local rip-backed shim.";
        })
        ""
        "# Auto-allowed command prefixes"
      ]
      ++ map (cmd: execPolicyRule { pattern = [ cmd ]; }) allowAllCommands
      ++ [
        ""
        "# Auto-allowed nix prefixes"
      ]
      ++ map (pattern: execPolicyRule { inherit pattern; }) allowedNixPatterns
      ++ [
        ""
        "# Destructive git prefixes that must ask first"
      ]
      ++ map execPolicyRule promptedGitRules
      ++ [
        ""
        "# Common rm bypass paths are forbidden"
      ]
      ++ map execPolicyRule forbiddenRmRules
    )
    + "\n";

  execPolicyManagedRulesFile = pkgs.writeText "codex-managed.rules" execPolicyManagedRules;
in
{
  inherit
    codexZshWrapper
    execPolicyManagedRulesFile
    rmShim
    ;
}
