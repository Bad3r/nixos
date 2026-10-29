{ pkgs, mkStampGuard }:
pkgs.writeShellApplication {
  name = "git-mirror-sync-repo";
  runtimeInputs = with pkgs; [
    git
    coreutils
    gawk
    psmisc
    util-linux
    python3
  ];
  text = ''
    set -eu
    spec="$1"
    max_backups="$GIT_MIRROR_MAX_BACKUPS"

    log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }

    retry_git() {
      label="$1"
      shift
      attempt=1
      delay=15

      while true; do
        if "$@"; then
          return 0
        else
          status="$?"
        fi
        if [ "$attempt" -ge 3 ]; then
          log "$spec: $label failed after $attempt attempts"
          return "$status"
        fi

        log "$spec: $label failed (attempt $attempt/3), retrying in ''${delay}s"
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
      done
    }

    run_maintenance() {
      # maintenance run exits 0 without running any task while this lock exists.
      lock="$(git -C "$dir" rev-parse --path-format=absolute --git-path objects/maintenance.lock)"
      # git holds the lock open for its whole run.
      if [ -e "$lock" ] && ! fuser -s "$lock"; then
        log "$spec: removing stale maintenance lock $lock"
        rm -f "$lock"
      fi
      if [ -e "$lock" ]; then
        log "$spec: maintenance lock $lock is held by a running process"
        exit 1
      fi
      git -C "$dir" -c maintenance.commit-graph.auto=1 maintenance run --auto || { log "$spec: maintenance failed"; exit 1; }
    }

    url_to_dir_name() {
      printf '%s\n' "$1" | awk '
        {
          value = $0
          sub(/^[[:alpha:]][[:alnum:].+-]*:\/\//, "", value)
          sub(/[?#].*$/, "", value)
          sub(/\/$/, "", value)
          sub(/\.git$/, "", value)
          count = split(value, parts, "/")
          host = parts[1]
          sub(/^www\./, "", host)
          sub(/\.(com|org|net)$/, "", host)
          output = host
          for (i = 2; i <= count; i++) {
            if (parts[i] != "") {
              output = output "-" parts[i]
            }
          }
          gsub(/[^[:alnum:]._-]/, "-", output)
          gsub(/-+/, "-", output)
          gsub(/^-|-$/, "", output)
          print output
        }'
    }

    case "$spec" in
      http://*|https://*)
        url="$spec"
        dir="$GIT_MIRROR_ROOT/$(url_to_dir_name "$spec")"
        ;;
      *)
        url="https://github.com/$spec.git"
        dir="$GIT_MIRROR_ROOT/$(printf '%s' "$spec" | tr '/' '-')"
        ;;
    esac

    # local-mirrors-root.service provisions the root only while the volume
    # holding it is mounted, so an absent root means an absent volume.
    # Ahead of the lock blocks below, not just of git clone: both docs lock
    # files sit directly in the root, so their mkdir -p would recreate it on
    # the root filesystem and hand every later spec a passing -d test.
    if [ ! -d "$GIT_MIRROR_ROOT" ]; then
      log "$spec: mirror root $GIT_MIRROR_ROOT is absent, is the volume mounted?"
      exit 1
    fi

    # local-mirrors-root.service writes the stamp, and its condition holds
    # only while the volume is mounted, so the stamp can exist only on that
    # volume. No mode bit can stand in for it: the tmpfiles rule this
    # replaced wrote 2775 onto the stray root it left on /, setgid
    # included, and any mkdir plus chmod g+s reproduces that.
    ${mkStampGuard {
      rootRef = "$GIT_MIRROR_ROOT";
      stampRef = "$GIT_MIRROR_STAMP_NAME";
      logPrefix = "$spec: ";
    }}

    if [ "''${GIT_MIRROR_FIREFOX_DOCS_REPO_SPEC:-}" = "$spec" ] && [ -n "''${GIT_MIRROR_FIREFOX_DOCS_LOCK_PATH:-}" ]; then
      lock_file="$GIT_MIRROR_FIREFOX_DOCS_LOCK_PATH"
      mkdir -p "$(dirname "$lock_file")"
      exec 9>"$lock_file"
      flock 9
    fi

    if [ "''${GIT_MIRROR_PYTHON_DOCS_REPO_SPEC:-}" = "$spec" ] && [ -n "''${GIT_MIRROR_PYTHON_DOCS_LOCK_PATH:-}" ]; then
      lock_file="$GIT_MIRROR_PYTHON_DOCS_LOCK_PATH"
      mkdir -p "$(dirname "$lock_file")"
      exec 8>"$lock_file"
      flock 8
    fi

    log "$spec: syncing"

    # Clone if missing
    if [ ! -d "$dir" ]; then
      retry_git "clone" git clone "$url" "$dir" || exit 1
      chmod g+s "$dir" || { log "$spec: chmod failed"; exit 1; }
      run_maintenance
      log "$spec: cloned"
      exit 0
    fi

    [ -d "$dir/.git" ] || { log "$spec: not a git repo"; exit 1; }

    # Fetch's auto-maintenance detaches.
    retry_git "fetch" git -C "$dir" -c maintenance.auto=false remote update --prune || exit 1

    # Stash dirty work
    if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
      git -C "$dir" stash push -m "git-mirror: $(date -u +%Y%m%dT%H%M%SZ)" || { log "$spec: stash failed"; exit 1; }
      # Prune old stashes (reverse order to avoid index shifting)
      git -C "$dir" stash list | awk -F: '/git-mirror:/ {print $1}' | tail -n +"$((max_backups + 1))" | \
        tac | xargs -r -I{} git -C "$dir" stash drop {} 2>/dev/null || true
    fi

    # Get tracking branch
    tracking=$(git -C "$dir" rev-parse --abbrev-ref '@{u}' 2>/dev/null) || \
      tracking="origin/$(git -C "$dir" remote show origin | awk '/HEAD branch/ {print $3}')"

    local_sha=$(git -C "$dir" rev-parse HEAD)
    remote_sha=$(git -C "$dir" rev-parse "$tracking")

    if [ "$local_sha" != "$remote_sha" ]; then
      python3 ${./_mirror-check-local-files.py} "$dir" "$remote_sha" || { log "$spec: local file check failed; refusing update"; exit 1; }
      # Backup diverging history
      if ! git -C "$dir" merge-base --is-ancestor HEAD "$tracking"; then
        backup="git-mirror/backup-$(date -u +%Y%m%dT%H%M%SZ)"
        git -C "$dir" branch "$backup" || { log "$spec: backup branch failed"; exit 1; }
        # A clock that stepped back would sort the new backup oldest.
        git -C "$dir" for-each-ref --sort=-refname --exclude="refs/heads/$backup" --format='%(refname:short)' \
          refs/heads/git-mirror/backup-* | tail -n +"$max_backups" | \
          xargs -r -I{} git -C "$dir" branch -D {} 2>/dev/null || true
      fi
      git -C "$dir" reset --keep "$remote_sha" || { log "$spec: update failed"; exit 1; }
    fi

    run_maintenance
    log "$spec: up to date"
  '';
}
