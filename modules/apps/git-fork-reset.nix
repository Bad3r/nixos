/*
  Package: git-fork-reset
  Description: Reset the current fork branch to the matching upstream branch.
  Homepage: nil
  Documentation: nil
  Repository: nil

  Summary:
    * Provides `git-fork-reset`, also invocable as `git fork-reset`, for refreshing fork branches from upstream.
    * Backs up dirty, untracked, and ignored local state with `git stash --all` before resetting.

  Options:
    --no-push: Reset locally without force-with-lease pushing to origin.
    --yes: Confirm the destructive reset without an interactive prompt.
    --dry-run: Print the Git operations that would run without changing the repository.
    --upstream <repo>: Add the upstream remote when missing, accepting owner/repo, GitHub URLs, or fully qualified Git remotes.
    --upstream-remote <name>: Use a remote name other than upstream.
    --origin-remote <name>: Use a push remote name other than origin.
    -h, --help: Print usage information.

  Notes:
    * The old shell function name is intentionally not preserved.
    * In Git subcommand form, use `git fork-reset -h`; Git handles `git fork-reset --help` as a manpage lookup.
    * The backup stash is kept for recovery and is never dropped automatically.
*/
_:
let
  GitForkResetModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."git-fork-reset".extended;

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

          run() {
            if $dry_run; then
              print_command "$@"
            else
              "$@"
            fi
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
          upstream_input=""
          upstream_remote="upstream"
          origin_remote="origin"

          while [[ $# -gt 0 ]]; do
            case "$1" in
              --no-push)
                push=false
                shift
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

          repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
            || die 'not inside a Git worktree'
          branch="$(git symbolic-ref --quiet --short HEAD)" \
            || die 'not on a branch; refusing to reset detached HEAD'

          if ! git remote get-url "$upstream_remote" >/dev/null 2>&1; then
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
            run git remote add "$upstream_remote" "$upstream_url"
          elif [[ -n "$upstream_input" ]]; then
            printf 'git fork-reset: %s remote already exists; ignoring --upstream\n' "$upstream_remote" >&2
          fi

          if $push && ! git remote get-url "$origin_remote" >/dev/null 2>&1; then
            die "no $origin_remote remote found"
          fi

          fetch_ref="+refs/heads/$branch:refs/remotes/$upstream_remote/$branch"
          target_ref="refs/remotes/$upstream_remote/$branch"

          run git fetch "$upstream_remote" "$fetch_ref"

          if $dry_run; then
            if git rev-parse --verify --quiet "$target_ref^{commit}" >/dev/null; then
              target_commit="$(git rev-parse --short "$target_ref")"
            else
              target_commit='unknown until fetch'
            fi
          else
            target_commit="$(git rev-parse --short "$target_ref")" \
              || die "fetched branch was not available at $target_ref"
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
            if $has_local_state; then
              print_command git stash push --all --message "$stash_message"
            fi
            print_command git switch "$branch"
            print_command git reset --hard "$target_ref"
            if $push; then
              print_command git push --force-with-lease "$origin_remote" "$branch:$branch"
            fi
            exit 0
          fi

          confirm_reset

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

          git switch "$branch"
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
      options.programs."git-fork-reset".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the git fork reset helper.";
        };

        package = lib.mkPackageOption pkgs "git" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ gitForkResetWrapper ];
      };
    };
in
{
  flake.nixosModules.apps."git-fork-reset" = GitForkResetModule;
}
