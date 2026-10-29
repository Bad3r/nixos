#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

worker="$(command -v git-mirror-sync-repo)"
docs_builder="$(command -v git-mirror-build-firefox-docs)"
test_root="$(mktemp -d)"
trap 'rm -r "$test_root"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$test_root/gitconfig"
export GIT_TERMINAL_PROMPT=0
export GIT_MIRROR_STAMP_NAME=.test-root-stamp
export GIT_MIRROR_MAX_BACKUPS=3

git config --global user.name 'Mirror sync test'
git config --global user.email mirror-test@example.invalid
git config --global commit.gpgsign false

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

new_case() {
  case_root="$test_root/$1"
  upstream="$case_root/upstream"
  export GIT_MIRROR_ROOT="$case_root/mirrors"
  spec="fixture/$1"
  mirror="$GIT_MIRROR_ROOT/fixture-$1"
  mkdir -p "$upstream" "$GIT_MIRROR_ROOT"
  touch "$GIT_MIRROR_ROOT/$GIT_MIRROR_STAMP_NAME"
  git -C "$upstream" init -q -b main
  printf 'initial\n' >"$upstream/source.txt"
  printf 'build/\n' >"$upstream/.gitignore"
  git -C "$upstream" add source.txt .gitignore
  git -C "$upstream" commit -qm initial
  git config --global "url.file://$upstream.insteadOf" "https://github.com/$spec.git"
  git clone -q "$upstream" "$mirror"
  git -C "$mirror" remote set-url origin "https://github.com/$spec.git"
  [[ $(git -C "$mirror" rev-parse HEAD) == "$(git -C "$upstream" rev-parse HEAD)" ]] || fail 'clone HEAD mismatch'
}

sync_ok() {
  "$worker" "$spec" >"$case_root/sync.log" 2>&1 || {
    cat "$case_root/sync.log" >&2
    fail 'mirror sync failed'
  }
  [[ $(git -C "$mirror" rev-parse HEAD) == "$(git -C "$upstream" rev-parse HEAD)" ]] || fail 'sync HEAD mismatch'
}

advance() {
  printf 'updated\n' >"$upstream/source.txt"
  git -C "$upstream" add source.txt
  git -C "$upstream" commit -qm update
}

new_case local-files
printf 'local instructions\n' >"$mirror/CLAUDE.md"
printf 'ignored instructions\n' >"$mirror/IGNORED.md"
printf 'IGNORED.md\n' >>"$mirror/.git/info/exclude"
printf 'odd filename\n' >"$mirror/"$'notes\nlocal.md'
mkdir -p "$mirror/build"
printf 'build cache\n' >"$mirror/build/cache"
advance
sync_ok
[[ $(cat "$mirror/CLAUDE.md") == 'local instructions' ]] || fail 'untracked instructions changed'
[[ $(cat "$mirror/IGNORED.md") == 'ignored instructions' ]] || fail 'ignored instructions changed'
[[ $(cat "$mirror/build/cache") == 'build cache' ]] || fail 'ignored build cache removed'
[[ $(cat "$mirror/"$'notes\nlocal.md') == 'odd filename' ]] || fail 'newline filename changed'
[[ -z $(git -C "$mirror" stash list) ]] || fail 'untracked-only checkout created a stash'
sync_ok
[[ -z $(git -C "$mirror" stash list) ]] || fail 'repeat sync created a stash'
git -C "$mirror" diff --exit-code -- .gitignore
printf '%s\n' 'ok: untracked and ignored files survive updates and repeated syncs'

printf 'local tracked edit\n' >"$mirror/source.txt"
printf 'staged addition\n' >"$mirror/staged.txt"
git -C "$mirror" add staged.txt
sync_ok
[[ $(cat "$mirror/source.txt") == updated ]] || fail 'tracked edit was not stashed'
[[ ! -e $mirror/staged.txt ]] || fail 'staged addition was not stashed'
[[ $(git -C "$mirror" show stash:source.txt) == 'local tracked edit' ]] || fail 'tracked edit missing from stash'
[[ $(git -C "$mirror" show stash:staged.txt) == 'staged addition' ]] || fail 'staged addition missing from stash'
[[ $(cat "$mirror/CLAUDE.md") == 'local instructions' ]] || fail 'stashing tracked edits removed instructions'
printf '%s\n' 'ok: tracked edits and staged additions are stashed without removing local files'

new_case diverged
printf 'local commit\n' >"$mirror/local.txt"
git -C "$mirror" add local.txt
git -C "$mirror" commit -qm local
local_head="$(git -C "$mirror" rev-parse HEAD)"
printf 'local instructions\n' >"$mirror/CLAUDE.md"
advance
sync_ok
backup="$(git -C "$mirror" for-each-ref --format='%(objectname)' refs/heads/git-mirror/)"
[[ $backup == "$local_head" ]] || fail 'diverged history was not backed up'
[[ $(cat "$mirror/CLAUDE.md") == 'local instructions' ]] || fail 'diverged sync removed instructions'
printf '%s\n' 'ok: diverged commits are backed up and local files remain'

for collision in untracked ignored local-directory local-file symlink; do
  new_case "$collision"
  before="$(git -C "$mirror" rev-parse HEAD)"
  case "$collision" in
  untracked | ignored)
    printf 'local instructions\n' >"$mirror/CLAUDE.md"
    if [[ $collision == ignored ]]; then
      printf 'CLAUDE.md\n' >>"$mirror/.git/info/exclude"
    fi
    printf 'upstream instructions\n' >"$upstream/CLAUDE.md"
    git -C "$upstream" add CLAUDE.md
    ;;
  local-directory)
    mkdir "$mirror/notes"
    printf 'local instructions\n' >"$mirror/notes/CLAUDE.md"
    printf 'upstream file\n' >"$upstream/notes"
    git -C "$upstream" add notes
    ;;
  local-file | symlink)
    printf 'local instructions\n' >"$case_root/local-content"
    if [[ $collision == symlink ]]; then
      ln -s "$case_root/local-content" "$mirror/notes"
    else
      cp "$case_root/local-content" "$mirror/notes"
    fi
    mkdir "$upstream/notes"
    printf 'upstream file\n' >"$upstream/notes/README.md"
    git -C "$upstream" add notes/README.md
    ;;
  esac
  git -C "$upstream" commit -qm collision
  if "$worker" "$spec" >"$case_root/sync.log" 2>&1; then
    fail "$collision collision was accepted"
  fi
  grep -Fq 'refusing to overwrite local path' "$case_root/sync.log" || fail 'collision cause missing'
  [[ $(git -C "$mirror" rev-parse HEAD) == "$before" ]] || fail 'collision changed HEAD'
  git -C "$mirror" diff --exit-code --cached
  case "$collision" in
  untracked | ignored) local_path="$mirror/CLAUDE.md" ;;
  local-directory) local_path="$mirror/notes/CLAUDE.md" ;;
  *) local_path="$mirror/notes" ;;
  esac
  [[ $(cat "$local_path") == 'local instructions' ]] || fail 'collision overwrote local content'
  printf 'ok: %s collision preserves HEAD, index and local content\n' "$collision"
done

mkdir -p "$test_root/firefox"
cd "$test_root/firefox"
touch .test-root-stamp
git init -q -b main
printf '#!%s\n' "$(command -v bash)" >mach
cat >>mach <<'MACH'
set -euo pipefail
while [[ $# -gt 0 ]]; do
  if [[ $1 == --outdir ]]; then
    outdir="$2"
    shift
  fi
  shift
done
mkdir -p "$outdir/html"
printf 'generated documentation\n' >"$outdir/html/index.html"
MACH
chmod +x mach
printf 'tracked source\n' >source.txt
git add mach source.txt
git commit -qm 'Firefox docs fixture'
printf 'local instructions\n' >CLAUDE.md
"$docs_builder" >docs.log 2>&1 || {
  cat docs.log >&2
  fail 'local instructions blocked Firefox docs'
}
[[ -s current/index.html ]] || fail 'Firefox docs were not published'
printf 'tracked edit\n' >source.txt
if "$docs_builder" >docs.log 2>&1; then
  fail 'Firefox docs accepted tracked edits'
fi
grep -Fq 'refusing to build from a dirty Firefox checkout' docs.log || fail 'tracked edit refusal missing'
printf '%s\n' 'ok: Firefox docs allow local instructions and reject tracked edits'
