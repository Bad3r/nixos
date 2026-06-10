{
  lib,
  pkgs,
  pythonDocs,
}:

pkgs.writeShellApplication {
  name = "git-mirror-publish-python-docs";
  runtimeInputs = with pkgs; [
    coreutils
    curl
    findutils
    git
    gnugrep
    gnused
    gnutar
    util-linux
  ];
  text = ''
    set -euo pipefail

    repo_path=${lib.escapeShellArg pythonDocs.repoPath}
    output_root=${lib.escapeShellArg pythonDocs.outputRoot}
    version_url=${lib.escapeShellArg pythonDocs.versionUrl}
    max_revisions=${lib.escapeShellArg (toString pythonDocs.maxRevisions)}
    lock_file=${lib.escapeShellArg pythonDocs.lockPath}
    tmp_revision=

    log() { printf '%s python-docs: %s\n' "$(date -Is)" "$*" >&2; }

    has_docs_source() {
      [ -f "$1/conf.py" ] && [ -f "$1/index.rst" ] && [ -d "$1/library" ]
    }

    cleanup_tmp() {
      if [ -n "''${tmp_revision:-}" ] && [ -d "$tmp_revision" ]; then
        find "$tmp_revision" -depth -mindepth 1 -delete
        rmdir "$tmp_revision"
      fi
    }

    prune_revisions() {
      [ -d "$output_root/revisions" ] || return 0

      find "$output_root/revisions" -mindepth 1 -maxdepth 1 -type d ! -name '.tmp-*' -printf '%T@ %p\0' |
        sort -z -nr |
        tail -z -n +"$((max_revisions + 1))" |
        while IFS= read -r -d "" entry; do
          old_path=''${entry#* }
          log "pruning old Python docs revision: $old_path"
          find "$old_path" -depth -mindepth 1 -delete
          rmdir "$old_path"
        done
    }

    resolve_stable_branch() {
      page=$(curl --fail --location --silent --show-error "$version_url")
      printf '%s\n' "$page" |
        sed -nE '/Python 3\.[0-9]+(\.[0-9]+)? [Dd]ocumentation/ {
          s/.*Python (3\.[0-9]+)(\.[0-9]+)? [Dd]ocumentation.*/\1/p
          q
        }'
    }

    trap cleanup_tmp EXIT

    mkdir -p "$(dirname "$lock_file")"
    exec 9>"$lock_file"
    flock 9

    if [ ! -d "$repo_path/.git" ]; then
      log "skipping; $repo_path is not a git checkout"
      exit 0
    fi

    branch=$(resolve_stable_branch)
    if [ -z "$branch" ]; then
      log "failed to resolve current stable Python branch from $version_url"
      exit 1
    fi

    remote_ref="refs/remotes/origin/$branch"
    if ! git -C "$repo_path" show-ref --verify --quiet "$remote_ref"; then
      log "fetching missing CPython branch $branch"
      git -C "$repo_path" fetch origin "+refs/heads/$branch:$remote_ref"
    fi

    if ! sha=$(git -C "$repo_path" rev-parse --verify "origin/$branch^{commit}" 2>/dev/null); then
      log "origin/$branch is not available in $repo_path"
      exit 1
    fi

    mkdir -p "$output_root/revisions"

    revision_root="$output_root/revisions/$branch-$sha"
    docs_dir="$revision_root/Doc"
    marker="$output_root/current-branch"
    publish_marker="$branch $sha $version_url"
    current_target=$(readlink "$output_root/current" 2>/dev/null || true)

    if [ -r "$marker" ] &&
      [ "$(cat "$marker")" = "$publish_marker" ] &&
      [ "$current_target" = "$docs_dir" ] &&
      has_docs_source "$docs_dir"; then
      touch "$revision_root"
      prune_revisions
      log "skipping; Python docs for $branch at $sha are already current"
      exit 0
    fi

    if [ -d "$revision_root" ] && ! has_docs_source "$docs_dir"; then
      log "removing incomplete Python docs revision: $revision_root"
      find "$revision_root" -depth -mindepth 1 -delete
      rmdir "$revision_root"
    fi

    if ! has_docs_source "$docs_dir"; then
      tmp_revision=$(mktemp -d "$output_root/revisions/.tmp-$branch-$sha.XXXXXX")
      git -C "$repo_path" archive "$sha" Doc | tar -x -C "$tmp_revision"
      if ! has_docs_source "$tmp_revision/Doc"; then
        log "expected CPython $branch Doc/ to contain conf.py, index.rst, and library/"
        exit 1
      fi
      mv -T "$tmp_revision" "$revision_root"
      tmp_revision=
    fi

    tmp_link="$output_root/current.tmp"
    ln -sfnT "$docs_dir" "$tmp_link"
    mv -Tf "$tmp_link" "$output_root/current"

    printf '%s\n' "$publish_marker" > "$marker.tmp"
    mv -Tf "$marker.tmp" "$marker"

    touch "$revision_root"
    prune_revisions

    log "published $output_root/current from CPython $branch at $sha"
  '';
}
