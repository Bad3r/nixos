{
  lib,
  pkgs,
  firefoxDocs,
}:

pkgs.writeShellApplication {
  name = "git-mirror-build-firefox-docs";
  runtimeInputs = with pkgs; [
    bash
    binutils
    coreutils
    findutils
    git
    gnugrep
    gnused
    nodejs
    patch
    python3
    util-linux
    which
  ];
  text = ''
    set -euo pipefail

    repo_path=${lib.escapeShellArg firefoxDocs.repoPath}
    output_root=${lib.escapeShellArg firefoxDocs.outputRoot}
    format_name=${lib.escapeShellArg firefoxDocs.format}
    max_revisions=${lib.escapeShellArg (toString firefoxDocs.maxRevisions)}
    lock_file=${lib.escapeShellArg firefoxDocs.lockPath}

    log() { printf '%s firefox-docs: %s\n' "$(date -Is)" "$*" >&2; }

    prune_artifacts() {
      prune_root="$1"
      label="$2"

      [ -d "$prune_root" ] || return 0

      find "$prune_root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\0' |
        sort -z -nr |
        tail -z -n +"$((max_revisions + 1))" |
        while IFS= read -r -d "" entry; do
          old_path=''${entry#* }
          log "pruning old Firefox docs $label: $old_path"
          find "$old_path" -depth -mindepth 1 -delete
          rmdir "$old_path"
        done
    }

    mkdir -p "$(dirname "$lock_file")"
    exec 9>"$lock_file"
    flock 9

    if [ ! -d "$repo_path/.git" ]; then
      log "skipping; $repo_path is not a git checkout"
      exit 0
    fi

    if [ ! -x "$repo_path/mach" ]; then
      log "skipping; $repo_path/mach is missing or not executable"
      exit 0
    fi

    if ! sha=$(git -C "$repo_path" rev-parse --verify HEAD 2>/dev/null); then
      log "skipping; $repo_path has no valid HEAD"
      exit 0
    fi

    dirty_before=$(git -C "$repo_path" status --porcelain --untracked-files=all)
    if [ -n "$dirty_before" ]; then
      log "refusing to build from a dirty Firefox checkout"
      printf '%s\n' "$dirty_before" >&2
      exit 1
    fi

    marker="$output_root/last-built-revision"
    current_index="$output_root/current/index.html"
    if [ -r "$marker" ] && [ "$(cat "$marker")" = "$sha" ] && [ -f "$current_index" ]; then
      log "skipping; docs for $sha are already current"
      exit 0
    fi

    revision_root="$output_root/revisions/$sha"
    savedir="$revision_root/$format_name"
    mkdir -p "$output_root/revisions" "$output_root/state" "$output_root/cache"

    args=(
      doc
      --format "$format_name"
      --outdir "$revision_root"
      --no-open
      --no-serve
    )
    ${lib.optionalString firefoxDocs.archive ''
      args+=(--archive)
    ''}
    ${lib.optionalString (firefoxDocs.jobs != null) ''
      args+=(-j ${lib.escapeShellArg (toString firefoxDocs.jobs)})
    ''}
    ${lib.optionalString firefoxDocs.disableWarningsCheck ''
      args+=(--disable-warnings-check)
    ''}
    ${lib.optionalString firefoxDocs.verbose ''
      args+=(--verbose)
    ''}
    ${lib.optionalString firefoxDocs.noAutodoc ''
      args+=(--no-autodoc)
    ''}
    ${lib.optionalString (firefoxDocs.path != null) ''
      args+=(${lib.escapeShellArg firefoxDocs.path})
    ''}

    log "building Firefox docs for $sha"
    (
      cd "$repo_path"
      MOZ_AUTOMATION=1 \
        MOZBUILD_STATE_PATH="$output_root/state" \
        XDG_CACHE_HOME="$output_root/cache" \
        ./mach "''${args[@]}"
    )

    ${lib.optionalString firefoxDocs.linkcheck ''
      linkcheck_root="$output_root/linkcheck/$sha"
      linkcheck_args=(
        doc
        --outdir "$linkcheck_root"
        --no-open
        --no-serve
        --linkcheck
      )
      ${lib.optionalString firefoxDocs.verbose ''
        linkcheck_args+=(--verbose)
      ''}
      ${lib.optionalString (firefoxDocs.path != null) ''
        linkcheck_args+=(${lib.escapeShellArg firefoxDocs.path})
      ''}

      log "checking Firefox docs links for $sha"
      (
        cd "$repo_path"
        MOZ_AUTOMATION=1 \
          MOZBUILD_STATE_PATH="$output_root/state" \
          XDG_CACHE_HOME="$output_root/cache" \
          ./mach "''${linkcheck_args[@]}"
      )
    ''}

    if [ ! -f "$savedir/index.html" ]; then
      log "expected $savedir/index.html after docs build"
      exit 1
    fi

    dirty_after=$(git -C "$repo_path" status --porcelain --untracked-files=all)
    if [ -n "$dirty_after" ]; then
      log "warning: Firefox checkout became dirty while building docs; git-mirror will clean it during the next sync"
      printf '%s\n' "$dirty_after" >&2
    fi

    tmp_link="$output_root/current.tmp"
    ln -sfnT "$savedir" "$tmp_link"
    mv -Tf "$tmp_link" "$output_root/current"

    printf '%s\n' "$sha" > "$marker.tmp"
    mv -Tf "$marker.tmp" "$marker"

    touch "$revision_root"
    ${lib.optionalString firefoxDocs.linkcheck ''
      touch "$linkcheck_root"
    ''}
    prune_artifacts "$output_root/revisions" "revision"
    prune_artifacts "$output_root/linkcheck" "linkcheck"

    log "published $output_root/current"
  '';
}
