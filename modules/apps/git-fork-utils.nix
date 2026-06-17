/*
  Package: git-fork-utils
  Description: Git fork maintenance utilities.
  Homepage: nil
  Documentation: nil
  Repository: nil

  Summary:
    * Provides `git-fork-sync`, also invocable as `git fork-sync`, for pulling fork branches from origin and upstream.
    * Provides `git-fork-reset`, also invocable as `git fork-reset`, for refreshing fork branches from upstream.
    * Backs up dirty, untracked, and ignored local state with `git stash --all` before resetting.

  Options:
    --no-push: Reset locally without force-with-lease pushing to origin.
    -c <path>: Run against a local repository path instead of the current directory.
    --yes: Confirm the destructive reset without an interactive prompt.
    --dry-run: Print the Git operations that would run without changing the repository.
    --upstream <repo>: Add the upstream remote when missing, accepting owner/repo, GitHub URLs, or fully qualified Git remotes.
    --upstream-remote <name>: Use a remote name other than upstream.
    --origin-remote <name>: Use a push remote name other than origin.
    -h, --help: Print usage information.

  Notes:
    * In Git subcommand form, use `git fork-sync -h` or `git fork-reset -h`; Git handles `--help` as a manpage lookup.
    * The backup stash is kept for recovery and is never dropped automatically.
*/
_:
let
  GitForkUtilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."git-fork-utils".extended;

      gitForkSyncWrapper = pkgs.writeShellApplication {
        name = "git-fork-sync";
        runtimeInputs = [ cfg.package ];
        text = ''
          usage() {
            cat <<'EOF'
          git-fork-sync - pull a fork branch from origin and upstream

          Usage:
            git-fork-sync [OPTIONS]
            git fork-sync [OPTIONS]

          Pulls the current branch from origin, pulls the same branch from
          upstream, then pushes the refreshed branch back to origin.

          Options:
            -c REPO_PATH              Run against this local repository path.
            -h, --help                Print this help and exit.

          Examples:
            git fork-sync
            git fork-sync -c /data/Projects/igit/fork-nixpkgs

          Note:
            Git handles `git fork-sync --help` as a manpage lookup. Use
            `git fork-sync -h` or `git-fork-sync --help` for this help text.
          EOF
          }

          die() {
            printf 'git fork-sync: %s\n' "$*" >&2
            exit 1
          }

          repo_path="."

          while [[ $# -gt 0 ]]; do
            case "$1" in
              -c)
                if [[ -z "''${2:-}" ]]; then
                  die '-c requires a repo path'
                fi
                repo_path="$2"
                shift 2
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              --)
                shift
                if [[ $# -gt 0 ]]; then
                  die 'unexpected positional arguments'
                fi
                break
                ;;
              -*)
                die "unknown option: $1"
                ;;
              *)
                die "unexpected argument: $1"
                ;;
            esac
          done

          cd -- "$repo_path" || die "cannot access repo path: $repo_path"

          git rev-parse --show-toplevel >/dev/null 2>&1 \
            || die 'not inside a Git worktree'
          branch="$(git symbolic-ref --quiet --short HEAD)" \
            || die 'not on a branch'

          git pull --no-edit origin "$branch" \
            && git pull --no-edit upstream "$branch" \
            && git push origin "$branch"
        '';
      };

      gitForkResetWrapper = pkgs.writeShellApplication {
        name = "git-fork-reset";
        runtimeInputs = [
          cfg.package
          pkgs.coreutils
        ];
        text = ''
          usage() {
            cat <<'EOF'
          git-fork-reset - reset a fork branch to the matching upstream branch

          Usage:
            git-fork-reset [OPTIONS]
            git fork-reset [OPTIONS]

          Resets the current branch to upstream/<current-branch>. If local
          tracked changes, untracked files, or ignored files are present, they
          are first captured with `git stash --all` and the stash is kept for
          recovery. By default, the refreshed branch is pushed to origin with
          --force-with-lease.

          Options:
            --no-push                 Reset locally without pushing origin.
            -c REPO_PATH              Run against this local repository path.
            -y, --yes                 Confirm without an interactive prompt.
            --dry-run                 Print operations without changing state.
            --upstream REPO           Upstream repo to add when the remote is missing.
                                      Accepts owner/repo, GitHub URLs, or fully
                                      qualified Git remotes.
            --upstream-remote NAME    Upstream remote name. Default: upstream.
            --origin-remote NAME      Push remote name. Default: origin.
            -h, --help                Print this help and exit.

          Examples:
            git fork-reset --yes
            git fork-reset -c /data/Projects/igit/fork-nixpkgs --yes
            git fork-reset --no-push
            git fork-reset --upstream NixOS/nixpkgs --yes
            git-fork-reset --dry-run

          Note:
            Git handles `git fork-reset --help` as a manpage lookup. Use
            `git fork-reset -h` or `git-fork-reset --help` for this help text.
          EOF
          }

          die() {
            printf 'git fork-reset: %s\n' "$*" >&2
            exit 1
          }

          print_command() {
            printf '+'
            printf ' %q' "$@"
            printf '\n'
          }

          confirm_reset() {
            if $assume_yes; then
              return 0
            fi

            if [[ ! -t 0 ]]; then
              die 'refusing to prompt with non-tty stdin; pass --yes to confirm'
            fi

            local reply
            read -r -p 'Reset this branch and discard the working tree? [y/N] ' reply
            case "''${reply,,}" in
              y|yes) ;;
              *) die 'aborted' ;;
            esac
          }

          normalize_upstream_url() {
            local input="$1"
            input="''${input%/}"

            if [[ -z "$input" ]]; then
              return 1
            fi

            case "$input" in
              https://github.com/*.git|git@github.com:*.git)
                printf '%s\n' "$input"
                ;;
              https://github.com/*|git@github.com:*)
                printf '%s.git\n' "$input"
                ;;
              github.com/*)
                printf 'https://%s.git\n' "''${input%.git}"
                ;;
              *://*|*@*:*)
                printf '%s\n' "$input"
                ;;
              [!./]*/[!./]*)
                if [[ "$input" == */*/* ]]; then
                  return 1
                fi
                printf 'https://github.com/%s.git\n' "''${input%.git}"
                ;;
              *)
                return 1
                ;;
            esac
          }

          validate_remote_name() {
            local label="$1"
            local name="$2"

            if [[ -z "$name" || "$name" == -* || "$name" == *[[:space:]]* ]]; then
              die "invalid $label remote name: $name"
            fi
          }

          push=true
          assume_yes=false
          dry_run=false
          repo_path="."
          upstream_input=""
          upstream_remote="upstream"
          origin_remote="origin"

          while [[ $# -gt 0 ]]; do
            case "$1" in
              --no-push)
                push=false
                shift
                ;;
              -c)
                if [[ -z "''${2:-}" ]]; then
                  die '-c requires a repo path'
                fi
                repo_path="$2"
                shift 2
                ;;
              -y|--yes)
                assume_yes=true
                shift
                ;;
              --dry-run)
                dry_run=true
                shift
                ;;
              --upstream)
                if [[ -z "''${2:-}" ]]; then
                  die '--upstream requires an argument'
                fi
                upstream_input="$2"
                shift 2
                ;;
              --upstream=*)
                upstream_input="''${1#*=}"
                if [[ -z "$upstream_input" ]]; then
                  die '--upstream= requires a non-empty argument'
                fi
                shift
                ;;
              --upstream-remote)
                if [[ -z "''${2:-}" ]]; then
                  die '--upstream-remote requires an argument'
                fi
                upstream_remote="$2"
                shift 2
                ;;
              --upstream-remote=*)
                upstream_remote="''${1#*=}"
                if [[ -z "$upstream_remote" ]]; then
                  die '--upstream-remote= requires a non-empty argument'
                fi
                shift
                ;;
              --origin-remote)
                if [[ -z "''${2:-}" ]]; then
                  die '--origin-remote requires an argument'
                fi
                origin_remote="$2"
                shift 2
                ;;
              --origin-remote=*)
                origin_remote="''${1#*=}"
                if [[ -z "$origin_remote" ]]; then
                  die '--origin-remote= requires a non-empty argument'
                fi
                shift
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              --)
                shift
                if [[ $# -gt 0 ]]; then
                  die 'unexpected positional arguments'
                fi
                break
                ;;
              -*)
                die "unknown option: $1"
                ;;
              *)
                die "unexpected argument: $1"
                ;;
            esac
          done

          validate_remote_name upstream "$upstream_remote"
          validate_remote_name origin "$origin_remote"

          cd -- "$repo_path" || die "cannot access repo path: $repo_path"

          repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
            || die 'not inside a Git worktree'
          branch="$(git symbolic-ref --quiet --short HEAD)" \
            || die 'not on a branch; refusing to reset detached HEAD'

          upstream_missing=false
          upstream_url=""
          if ! git remote get-url "$upstream_remote" >/dev/null 2>&1; then
            upstream_missing=true
            if [[ -z "$upstream_input" ]]; then
              if [[ ! -t 0 ]]; then
                die "no $upstream_remote remote found; pass --upstream"
              fi
              printf 'No %s remote found.\n' "$upstream_remote"
              printf 'Enter upstream repo, e.g. NixOS/nixpkgs or https://github.com/NixOS/nixpkgs.git: '
              IFS= read -r upstream_input
            fi

            upstream_url="$(normalize_upstream_url "$upstream_input")" \
              || die "invalid upstream repo: $upstream_input"
          elif [[ -n "$upstream_input" ]]; then
            printf 'git fork-reset: %s remote already exists; ignoring --upstream\n' "$upstream_remote" >&2
          fi

          if $push && ! git remote get-url "$origin_remote" >/dev/null 2>&1; then
            die "no $origin_remote remote found"
          fi

          fetch_ref="+refs/heads/$branch:refs/remotes/$upstream_remote/$branch"
          target_ref="refs/remotes/$upstream_remote/$branch"

          if git rev-parse --verify --quiet "$target_ref^{commit}" >/dev/null; then
            target_commit="$(git rev-parse --short "$target_ref")"
          else
            target_commit='unknown until fetch'
          fi

          dirty_output="$(git status --porcelain --untracked-files=all --ignored=matching)"
          has_local_state=false
          if [[ -n "$dirty_output" ]]; then
            has_local_state=true
          fi

          printf 'Repository: %s\n' "$repo_root"
          printf 'Branch: %s\n' "$branch"
          printf 'Reset target: %s (%s)\n' "$target_ref" "$target_commit"
          if $has_local_state; then
            printf 'Local state: will be backed up with git stash --all before reset\n'
          else
            printf 'Local state: clean\n'
          fi
          if $push; then
            printf 'Push: %s %s:%s with --force-with-lease\n' "$origin_remote" "$branch" "$branch"
          else
            printf 'Push: skipped because --no-push was passed\n'
          fi

          timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
          stash_message="git-fork-reset backup: $branch $timestamp"

          if $dry_run; then
            if $upstream_missing; then
              print_command git remote add "$upstream_remote" "$upstream_url"
            fi
            print_command git fetch "$upstream_remote" "$fetch_ref"
            if $has_local_state; then
              print_command git stash push --all --message "$stash_message"
            fi
            print_command git reset --hard "$target_ref"
            if $push; then
              print_command git push --force-with-lease "$origin_remote" "$branch:$branch"
            fi
            exit 0
          fi

          confirm_reset

          if $upstream_missing; then
            git remote add "$upstream_remote" "$upstream_url"
          fi

          git fetch "$upstream_remote" "$fetch_ref"
          target_commit="$(git rev-parse --short "$target_ref")" \
            || die "fetched branch was not available at $target_ref"
          printf 'Fetched target: %s (%s)\n' "$target_ref" "$target_commit"

          if $has_local_state; then
            stash_before="$(git rev-parse --verify --quiet refs/stash || true)"
            git stash push --all --message "$stash_message"
            stash_after="$(git rev-parse --verify --quiet refs/stash || true)"
            if [[ -n "$stash_after" && "$stash_after" != "$stash_before" ]]; then
              stash_line="$(git stash list --format='%gd %h %s' -n 1)"
              printf 'Backup created: %s\n' "$stash_line"
            else
              die 'expected to create a backup stash, but refs/stash did not change'
            fi
          fi

          git reset --hard "$target_ref"

          if $push; then
            git push --force-with-lease "$origin_remote" "$branch:$branch"
          else
            printf 'Skipped push because --no-push was passed.\n'
          fi
        '';
      };
    in
    {
      options.programs."git-fork-utils".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the git fork utility helpers.";
        };

        package = lib.mkPackageOption pkgs "git" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          gitForkSyncWrapper
          gitForkResetWrapper
        ];
      };
    };
in
{
  flake.nixosModules.apps."git-fork-utils" = GitForkUtilsModule;
}
