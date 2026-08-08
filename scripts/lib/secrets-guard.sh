# shellcheck shell=bash
# Sourced by build.sh and scripts/cache-coverage.sh. Not executable on its own.
#
# The bare `.` form fetches through git, so .gitignore kept ignored files out of
# the store. path: dumps the tree, so the secrets block stops protecting
# anything the moment a caller switches refs. Both callers reach that copy on
# the same two conditions, a linked worktree and --allow-dirty, so the scan
# lives here rather than in either one.
#
# Colours are read from the caller when it defines them, so build.sh keeps its
# formatting and a caller without a palette gets the same text unstyled.

secrets_guard_notice() {
  printf '%b==> %b%s%b\n' "${YELLOW:-}" "${NC:-}" "$1" "${NC:-}"
}

secrets_guard_error() {
  printf '%bError:%b %s\n' "${RED:-}" "${NC:-}" "$1" >&2
}

# Reads the deny and allow arrays of secrets_guard_paths, which is the only
# caller: bash scopes locals dynamically, so both scans classify through one
# copy of the rules rather than two that can drift apart.
secrets_guard_is_hit() {
  local file="$1"
  local pattern rest
  for pattern in "${allow[@]}"; do
    # shellcheck disable=SC2053 # unquoted RHS on purpose: these are globs
    if [[ ${file##*/} == ${pattern} ]]; then
      return 1
    fi
  done
  # Every path component, not just the basename. ls-files reports the files
  # inside an ignored directory rather than the directory itself, so
  # id_backup/ or .env.d/ is copied whole while none of its children match.
  rest="${file}"
  while :; do
    for pattern in "${deny[@]}"; do
      # shellcheck disable=SC2053
      if [[ ${rest##*/} == ${pattern} ]]; then
        return 0
      fi
    done
    [[ ${rest} == */* ]] || break
    rest="${rest%/*}"
  done
  return 1
}

# git ls-files --error-unmatch answers three ways, not two: 0 tracked, 1 not
# tracked, 128 a git failure such as an unreadable index, a pruned gitdir or a
# broken object store. Collapsing that to a boolean reads a broken repository as
# a foreign tree and skips the scan, which is the fail-open every other git call
# here refuses; the raw status goes back so each caller can split it.
secrets_guard_tracked() {
  local dir="$1"
  local path="$2"
  local rc=0
  git -C "${dir}" ls-files --error-unmatch -- "${path}" >/dev/null 2>&1 || rc=$?
  return "${rc}"
}

secrets_guard_paths() {
  local dir="$1"
  local -a deny=() allow=()
  local line negated
  while IFS= read -r line; do
    negated=0
    if [[ ${line} == '!'* ]]; then
      negated=1
      line="${line#!}"
    fi
    # Reduced to the last component, because these are matched per path
    # component below rather than as git ignore rules. A directory prefix in the
    # block is there to stop git applying a pattern outside the tree it belongs
    # to (secrets/**/decrypted_* is inert for git, which never descends into the
    # gitlink), and dropping it here is what still lets the scan recognise the
    # name wherever path: copies it from, a bare decrypted_* at the superproject
    # root included: the anchor scopes git's ignore rule, not this scan, so
    # git check-ignore does not confirm that hit. The negation is stripped
    # first, since it precedes the prefix rather than the name.
    line="${line##*/}"
    if [[ ${negated} -eq 1 ]]; then
      allow+=("${line}")
    else
      deny+=("${line}")
    fi
    # Patterns are read from .gitignore rather than restated here: that file is
    # generated from modules/files.nix, so a second copy would drift unseen.
  done < <(awk '
    /^# Secrets safety \(defense-in-depth\)/ { in_block = 1; next }
    in_block && /^#/ { next }
    in_block && /^[[:space:]]*$/ { exit }
    in_block { print }
  ' "${dir}/.gitignore")

  # Fail closed on a partial parse, not just an empty one. The block ends at the
  # first blank line, so one inserted mid-block (the natural spot is before the
  # "# Common SSH/private key patterns" comment) leaves deny non-empty while
  # dropping id_*, and a count check cannot see that. managed-files-drift cannot
  # either, since .gitignore would still match its source. The minimum set is
  # named here rather than parsed: a legitimate change to the block then fires
  # loudly instead of thinning the deny list in silence.
  local want have
  local -a missing=()
  for want in '*.agekey' '*.key' '*.pem' '*.p12' '*.pfx' '.env' '.env.*' 'id_*' 'decrypted_*' '*.dec.*'; do
    have=0
    for line in "${deny[@]}"; do
      if [[ ${line} == "${want}" ]]; then
        have=1
        break
      fi
    done
    if [[ ${have} -eq 0 ]]; then
      missing+=("${want}")
    fi
  done
  if [[ ${#deny[@]} -eq 0 || ${#missing[@]} -gt 0 ]]; then
    secrets_guard_error "The '# Secrets safety (defense-in-depth)' block of ${dir}/.gitignore did not yield the expected patterns (missing: ${missing[*]:-every pattern}); the secrets guard cannot run. Realign this parser with modules/development/gitignore.nix, or pass --allow-secret-copy to continue anyway."
    return 1
  fi

  # --others with no exclude option is every untracked path, ignored or not,
  # which is exactly what path: adds over the git+file fetcher: that one carries
  # the tracked tree and nothing else. Restricting this to the ignored subset
  # missed anything the secrets block does not name, and the block cannot name a
  # secret whose pattern belongs to another tree, such as the decrypted SOPS
  # output secrets/ ignores through its own .gitignore.
  #
  # Every git call below fails closed. A scan that errors reads as "nothing to
  # copy" otherwise, which is the same silent pass the parser branch above
  # refuses. Input and output are both NUL delimited and both go through files
  # rather than command substitution, which strips NUL: a path containing a
  # newline would otherwise match no pattern on the way in, and be reported as
  # two paths that do not exist on the way out.
  local scan
  scan="$(mktemp)"
  local file
  if ! git -C "${dir}" ls-files --others -z >"${scan}"; then
    rm -f "${scan}"
    secrets_guard_error "Listing untracked files in ${dir} failed, so the secrets guard cannot scan it; path: copies the tree unfiltered."
    return 1
  fi
  # A trailing slash is ls-files declining to descend into an untracked
  # directory that is itself a git repository, which it reports once and never
  # opens. path: has no such boundary and copies the whole thing, so a scratch
  # clone parks its .env in the store while the deny list only ever sees the
  # directory name. Nothing inside was classified, so the boundary is the hit;
  # --allow-secret-copy is the way past a scratch tree that holds no secret.
  while IFS= read -r -d '' file; do
    if [[ ${file} == */ ]] || secrets_guard_is_hit "${file}"; then
      printf '%s\0' "${file}"
    fi
  done <"${scan}"

  # ls-files stops at a gitlink, but path: copies submodule working trees whole.
  # secrets/ keeps decrypted SOPS output out of its own history through
  # **/decrypted_* and *.dec.*, which the secrets block mirrors so this pass can
  # classify with the same rules; without them it would have to report every
  # untracked file it finds here, including build output and editor leftovers.
  local sub subfile submodules
  # shellcheck disable=SC2016 # git submodule foreach expands $displaypath itself
  if ! submodules="$(git -C "${dir}" submodule --quiet foreach --recursive 'printf "%s\n" "$displaypath"')"; then
    rm -f "${scan}"
    secrets_guard_error "Enumerating submodules of ${dir} failed, so the secrets guard cannot scan them; path: copies submodule working trees whole."
    return 1
  fi
  while IFS= read -r sub; do
    [[ -n ${sub} ]] || continue
    if ! git -C "${dir}/${sub}" ls-files --others -z >"${scan}"; then
      rm -f "${scan}"
      secrets_guard_error "Listing untracked files in submodule ${sub} failed, so the secrets guard cannot scan it; path: copies its working tree whole."
      return 1
    fi
    # The same boundary one level down: a stray repository nested in the
    # submodule's own untracked tree stops ls-files there too. foreach walks
    # registered submodules, so this pass reaches those and not these.
    while IFS= read -r -d '' subfile; do
      if [[ ${subfile} == */ ]] || secrets_guard_is_hit "${sub}/${subfile}"; then
        printf '%s\0' "${sub}/${subfile}"
      fi
    done <"${scan}"
  done <<<"${submodules}"
  rm -f "${scan}"
}

# Returns 0 when the tree is clear or the scan does not apply, 1 when ignored
# files would be copied, 2 when the guard itself could not run. The caller owns
# the exit code and the refusal wording, since a build and a coverage report
# abort for different reasons; everything actionable is printed here.
# "${copier}" names whatever performs the copy on this run.
secrets_guard_enforce() {
  local dir="$1"
  local copier="$2"

  if [[ ${ALLOW_SECRET_COPY:-false} == "true" || ${ALLOW_SECRET_COPY:-false} == "1" ]]; then
    return 0
  fi
  # Without this, --flake-dir pointed at a flake that is not a git worktree
  # reaches the missing-.gitignore abort below and is told to run write-files,
  # which does not own that directory. No git worktree means no ignore set, so
  # there is nothing for path: to smuggle past .gitignore.
  if ! command -v git >/dev/null 2>&1 || ! git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    secrets_guard_notice "${dir} is not a git worktree; nothing defines an ignore set, so the secrets scan does not run."
    return 0
  fi
  # Fail closed only on drift, which is tracked-but-absent: that is the state
  # modules/development/gitignore.nix can produce here. A foreign flake reached
  # through --flake-dir may simply never have had a .gitignore, and telling its
  # operator to run write-files names a file this repo does not generate there.
  if [[ ! -f "${dir}/.gitignore" ]]; then
    local gitignore_rc=0
    secrets_guard_tracked "${dir}" .gitignore || gitignore_rc=$?
    if [[ ${gitignore_rc} -gt 1 ]]; then
      secrets_guard_error "Checking whether ${dir} tracks .gitignore failed (git exit ${gitignore_rc}), so the secrets guard cannot tell drift from a tree that never had one."
      return 2
    fi
    if [[ ${gitignore_rc} -eq 0 ]]; then
      secrets_guard_error "${dir}/.gitignore is tracked but absent from the worktree, so the secrets guard cannot run. Restore it with write-files, or pass --allow-secret-copy to continue anyway."
      return 2
    fi
    secrets_guard_notice "${dir} has no .gitignore, so no secrets block defines patterns there; the secrets scan does not run."
    return 0
  fi
  # grep is the one external here whose absence is silent rather than loud: not
  # found returns 127, which negates to true and skips the scan below in any
  # tree that does not track the generator. awk, mktemp and the git calls in
  # secrets_guard_paths all fail closed on their own.
  if ! command -v grep >/dev/null 2>&1; then
    secrets_guard_error "grep was not found, so the secrets guard cannot run. Put it on PATH, or pass --allow-secret-copy to continue anyway."
    return 2
  fi

  # The same discriminator one level down. The block is this repo's convention,
  # emitted by modules/development/gitignore.nix, and practically every other
  # repository has a .gitignore without it; aborting there would name a module
  # that tree does not contain. A renamed or thinned heading in a tree that does
  # own the generator still fails closed in the parser.
  if ! grep -qxF '# Secrets safety (defense-in-depth)' "${dir}/.gitignore"; then
    # Reached only when the heading is already missing, which is the drift case
    # that has to fail closed, so a git failure here cannot be read as "foreign
    # tree". A tracked generator falls through to the parser, which aborts.
    local generator_rc=0
    secrets_guard_tracked "${dir}" modules/development/gitignore.nix || generator_rc=$?
    if [[ ${generator_rc} -gt 1 ]]; then
      secrets_guard_error "Checking whether ${dir} tracks modules/development/gitignore.nix failed (git exit ${generator_rc}), so the secrets guard cannot tell drift from a foreign tree."
      return 2
    fi
    if [[ ${generator_rc} -eq 1 ]]; then
      secrets_guard_notice "${dir}/.gitignore has no secrets block and the tree does not own modules/development/gitignore.nix, so it is not generated from this repo; the secrets scan does not run."
      return 0
    fi
  fi

  # `if !` keeps set -e suspended, so a parser failure reports itself instead of
  # reaching an ERR trap as a bare "Command 'return 1' failed". The hits land in
  # a file rather than a command substitution, which cannot carry the NUL that
  # keeps one path per element.
  local hits_file
  hits_file="$(mktemp)"
  if ! secrets_guard_paths "${dir}" >"${hits_file}"; then
    rm -f "${hits_file}"
    return 2
  fi
  local -a hit_list=()
  mapfile -d '' -t hit_list <"${hits_file}"
  rm -f "${hits_file}"
  if [[ ${#hit_list[@]} -eq 0 ]]; then
    return 0
  fi

  secrets_guard_error "Untracked paths that ${copier} would copy into the world-readable store, which the git+file fetcher would have left behind, either matching the .gitignore secrets block or impossible to scan. Submodule working trees are scanned too, with the same patterns, since path: copies them whole."
  # git check-ignore is the obvious way to confirm a hit, and it disagrees for
  # any pattern the block anchors to a subdirectory, so say why before the list
  # rather than let the operator read the disagreement as a false positive.
  printf 'A pattern the block anchors to a subdirectory is matched by name here, so git check-ignore will not confirm every hit: the anchor scopes git ignore rules, not this scan.\n' >&2
  # Name the second basis once rather than per entry, and only when the list
  # holds one: an operator who reads every hit as a pattern match goes looking
  # for the pattern a directory name never matched.
  local hit
  for hit in "${hit_list[@]}"; do
    if [[ ${hit} == */ ]]; then
      printf 'A trailing slash marks an untracked directory that is itself a git repository. ls-files stops at one, so nothing inside it was compared against the block, while path: copies it whole.\n' >&2
      break
    fi
  done
  # Report the truncation. The next line asks for all of them to be moved, so a
  # silent cap reads as a complete list and sends the operator back into the
  # same abort with no idea how much is left.
  printf '%s\n' "${hit_list[@]:0:50}" >&2
  if [[ ${#hit_list[@]} -gt 50 ]]; then
    printf '... and %d more not shown.\n' "$((${#hit_list[@]} - 50))" >&2
  fi
  printf "Move them outside the worktree, or pass --allow-secret-copy (ALLOW_SECRET_COPY=1) to override.\n" >&2
  return 1
}
