# shellcheck shell=bash
# Sourced by build.sh and scripts/cache-coverage.sh. Not executable on its own.
#
# The bare `.` form fetches through git, so .gitignore kept ignored files out of
# the store. path: dumps the tree, so the secrets block stops protecting
# anything the moment a caller switches refs. Both callers reach that copy:
# build.sh through resolve_installable, cache-coverage.sh through a hardcoded
# FLAKE_REF, so the scan lives here rather than in either one.
#
# Colours are read from the caller when it defines them, so build.sh keeps its
# formatting and a caller without a palette gets the same text unstyled.

secrets_guard_notice() {
  printf '%b==> %b%s%b\n' "${YELLOW:-}" "${NC:-}" "$1" "${NC:-}"
}

secrets_guard_error() {
  printf '%bError:%b %s\n' "${RED:-}" "${NC:-}" "$1" >&2
}

secrets_guard_paths() {
  local dir="$1"
  local -a deny=() allow=()
  local line
  while IFS= read -r line; do
    if [[ ${line} == '!'* ]]; then
      allow+=("${line#!}")
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
  for want in '*.agekey' '*.key' '*.pem' '*.p12' '*.pfx' '.env' '.env.*' 'id_*'; do
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

  # Every git call below fails closed. A scan that errors reads as "no ignored
  # files" otherwise, which is the same silent pass the parser branch above
  # refuses. Output goes through a temp file rather than command substitution so
  # -z survives: substitution strips NUL, and without it a path containing a
  # newline splits into two lines that match no pattern.
  local scan
  scan="$(mktemp)"
  local file base pattern rest
  if ! git -C "${dir}" ls-files --others --ignored --exclude-standard -z >"${scan}"; then
    rm -f "${scan}"
    secrets_guard_error "Listing ignored files in ${dir} failed, so the secrets guard cannot scan it; path: copies the tree unfiltered."
    return 1
  fi
  while IFS= read -r -d '' file; do
    base="${file##*/}"
    for pattern in "${allow[@]}"; do
      # shellcheck disable=SC2053 # unquoted RHS on purpose: these are globs
      if [[ ${base} == ${pattern} ]]; then
        continue 2
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
          printf '%s\n' "${file}"
          continue 3
        fi
      done
      [[ ${rest} == */* ]] || break
      rest="${rest%/*}"
    done
  done <"${scan}"

  # ls-files stops at a gitlink, but path: copies submodule working trees whole.
  # secrets/ ignores decrypted SOPS output through its own .gitignore
  # (**/decrypted_*, *.dec.*), and those names match none of the superproject
  # patterns above, so every ignored file found there is reported rather than
  # only secrets-block matches.
  local sub subfile submodules
  # shellcheck disable=SC2016 # git submodule foreach expands $displaypath itself
  if ! submodules="$(git -C "${dir}" submodule --quiet foreach --recursive 'printf "%s\n" "$displaypath"')"; then
    rm -f "${scan}"
    secrets_guard_error "Enumerating submodules of ${dir} failed, so the secrets guard cannot scan them; path: copies submodule working trees whole."
    return 1
  fi
  while IFS= read -r sub; do
    [[ -n ${sub} ]] || continue
    if ! git -C "${dir}/${sub}" ls-files --others --ignored --exclude-standard -z >"${scan}"; then
      rm -f "${scan}"
      secrets_guard_error "Listing ignored files in submodule ${sub} failed, so the secrets guard cannot scan it; path: copies its working tree whole."
      return 1
    fi
    while IFS= read -r -d '' subfile; do
      printf '%s\n' "${sub}/${subfile}"
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
    if git -C "${dir}" ls-files --error-unmatch -- .gitignore >/dev/null 2>&1; then
      secrets_guard_error "${dir}/.gitignore is tracked but absent from the worktree, so the secrets guard cannot run. Restore it with write-files, or pass --allow-secret-copy to continue anyway."
      return 2
    fi
    secrets_guard_notice "${dir} has no .gitignore, so no secrets block defines patterns there; the secrets scan does not run."
    return 0
  fi

  # `if !` keeps set -e suspended, so a parser failure reports itself instead of
  # reaching an ERR trap as a bare "Command 'return 1' failed".
  local hits
  if ! hits="$(secrets_guard_paths "${dir}")"; then
    return 2
  fi
  if [[ -z ${hits} ]]; then
    return 0
  fi

  # The two sets differ, so the heading names both: a submodule hit is any
  # ignored file, not a secrets-block match, since decrypted_* and *.dec.*
  # match none of the superproject patterns.
  secrets_guard_error "Ignored files that ${copier} would copy into the world-readable store. Paths outside a submodule matched the .gitignore secrets block; paths under a submodule are every ignored file there, because submodule ignore rules do not match the superproject patterns."
  # Report the truncation. The next line asks for all of them to be moved, so a
  # silent cap reads as a complete list and sends the operator back into the
  # same abort with no idea how much is left.
  local hit_count
  hit_count="$(printf '%s\n' "${hits}" | wc -l)"
  printf '%s\n' "${hits}" | sed -n '1,50p' >&2
  if [[ ${hit_count} -gt 50 ]]; then
    printf '... and %d more not shown.\n' "$((hit_count - 50))" >&2
  fi
  printf "Move them outside the worktree, or pass --allow-secret-copy (ALLOW_SECRET_COPY=1) to override.\n" >&2
  return 1
}
