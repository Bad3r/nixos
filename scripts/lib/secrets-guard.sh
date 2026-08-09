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

# Both diagnostics go to stderr, unlike the status_msg/error_msg pair in build.sh
# they otherwise mirror: cache-coverage.sh writes its report to stdout, and the
# skip notices all fire before the report header, so a stdout notice lands inside
# a redirected report. build.sh loses nothing, since setup_logging merges stderr
# into stdout before the tee.
secrets_guard_notice() {
  printf '%b==> %b%s%b\n' "${YELLOW:-}" "${NC:-}" "$1" "${NC:-}" >&2
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

# Every hit goes through here, because a hit that cannot be written is a hit the
# caller never sees, and an empty list reads as a clear tree. The destination is
# this function's stdout, which the caller owns and this one never created, so
# the remedy names no path of its own; TMPDIR is only where the one production
# caller happens to put it.
secrets_guard_emit() {
  local path="$1"
  local where="$2"
  printf '%s\0' "${path}" && return 0
  secrets_guard_error "Writing the hit list for ${where} failed, so the secrets guard found a path it cannot report and cannot certify the tree. Free space wherever its output is being written, commonly TMPDIR, or pass --allow-secret-copy to continue anyway."
  return 1
}

secrets_guard_paths() {
  local dir="$1"
  local -a deny=() allow=()
  local line raw negated
  # Read through a variable rather than a process substitution, which discards
  # awk's status: an unreadable .gitignore printed nothing, deny came back empty
  # and the minimum-set check below blamed the block, which is the same wrong
  # cause a3849cc1 preflighted awk to prevent and 62887039 split out of grep.
  # secrets_guard_enforce now gates this on grep reading the same file, so the
  # production route needs the mode to change in between; the suite's scan()
  # helper calls this directly, and that is the entry point covered here.
  local block awk_rc=0
  block="$(awk '
    /^# Secrets safety \(defense-in-depth\)/ { in_block = 1; next }
    in_block && /^#/ { next }
    in_block && /^[[:space:]]*$/ { exit }
    in_block { print }
  ' "${dir}/.gitignore")" || awk_rc=$?
  if [[ ${awk_rc} -ne 0 ]]; then
    secrets_guard_error "Reading ${dir}/.gitignore failed (awk exit ${awk_rc}), so the secrets guard could not parse the secrets block rather than finding it changed. Fix its permissions, or pass --allow-secret-copy to continue anyway."
    return 1
  fi
  while IFS= read -r line; do
    # An empty block reaches the herestring as one empty line, where the process
    # substitution gave no iterations; awk never prints one, since a blank line
    # inside the block ends it.
    [[ -n ${line} ]] || continue
    raw="${line}"
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
    #
    # The trailing slash goes before that reduction, not with it: a
    # directory-only rule such as secrets/keys/ is all prefix, so */ consumes
    # the whole entry and deny gains an empty pattern, which matches no path
    # component and is therefore inert. The minimum-set check below cannot see
    # it, since a new rule adds an entry rather than removing one of the ten it
    # names, so this is the thinning-in-silence that check exists to refuse.
    line="${line%/}"
    line="${line##*/}"
    # Whatever still reduces to nothing (a bare / or a doubled foo//) aborts
    # rather than being skipped: a block entry dropped quietly is the same
    # silent thinning, and no pattern this generator emits reaches here.
    if [[ -z ${line} ]]; then
      secrets_guard_error "The '# Secrets safety (defense-in-depth)' block of ${dir}/.gitignore holds '${raw}', which reduces to no name to match, so the secrets guard would enforce a thinner block than the file declares. Give that entry a name in modules/development/gitignore.nix, or pass --allow-secret-copy to continue anyway."
      return 1
    fi
    if [[ ${negated} -eq 1 ]]; then
      allow+=("${line}")
    else
      deny+=("${line}")
    fi
    # Patterns are read from .gitignore rather than restated here: that file is
    # generated from modules/files.nix, so a second copy would drift unseen.
  done <<<"${block}"

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
  #
  # Checked, because the preflight proves mktemp is present and not that it
  # works: a read-only or missing TMPDIR, or a full filesystem, leaves scan
  # empty, and the ls-files redirect below then fails before git runs at all.
  # That reported "Listing untracked files failed", naming a call that never
  # happened, which is the same misattribution the preflight was added to stop.
  local scan
  if ! scan="$(mktemp)"; then
    secrets_guard_error "Creating a temporary file for the scan of ${dir} failed (TMPDIR=${TMPDIR:-/tmp}), so the secrets guard cannot run and the untracked listing below never started. Point TMPDIR at a writable filesystem, or pass --allow-secret-copy to continue anyway."
    return 1
  fi
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
  #
  # The read is checked as well as the write. A redirect that cannot open the
  # file skips the loop entirely rather than failing it, so an unreadable scan
  # would classify nothing and still fall through to the return 0 below. An
  # empty but readable file is status 0, which is the clean tree this has to
  # keep telling apart.
  # Both statuses leave the loop in a variable rather than aborting inside it,
  # so the one cleanup stays outside the redirect that is reading the file it
  # removes. break leaves the loop status 0, which keeps the two apart.
  local read_rc=0 emit_rc=0
  while IFS= read -r -d '' file; do
    if [[ ${file} == */ ]] || secrets_guard_is_hit "${file}"; then
      if ! secrets_guard_emit "${file}" "${dir}"; then
        emit_rc=1
        break
      fi
    fi
  done <"${scan}" || read_rc=$?
  if [[ ${emit_rc} -ne 0 ]]; then
    rm -f "${scan}"
    return 1
  fi
  if [[ ${read_rc} -ne 0 ]]; then
    rm -f "${scan}"
    secrets_guard_error "Reading the untracked listing of ${dir} back failed, so the secrets guard classified none of what it listed. Check the filesystem holding TMPDIR, or pass --allow-secret-copy to continue anyway."
    return 1
  fi

  # ls-files stops at a gitlink, but path: copies submodule working trees whole.
  # secrets/ keeps decrypted SOPS output out of its own history through
  # **/decrypted_* and *.dec.*, which the secrets block mirrors so this pass can
  # classify with the same rules; without them it would have to report every
  # untracked file it finds here, including build output and editor leftovers.
  #
  # NUL delimited and through a file, for the reason the two scans are: a
  # newline-separated command substitution splits one submodule into two names
  # that do not exist, and unlike the file-path case that fails open. A
  # `path = "lib\nkeys"` in .gitmodules is refused by `git submodule add` and
  # accepted from the file, and git config hands the embedded newline straight
  # to foreach; the halves then land on an ordinary untracked lib/ that lists
  # clean, so no abort fires and the real working tree, which path: copies
  # whole, is never scanned.
  local sub subfile submodules
  if ! submodules="$(mktemp)"; then
    secrets_guard_error "Creating a temporary file for the submodule list of ${dir} failed (TMPDIR=${TMPDIR:-/tmp}), so the secrets guard cannot scan submodules and the enumeration below never started. Point TMPDIR at a writable filesystem, or pass --allow-secret-copy to continue anyway."
    rm -f "${scan}"
    return 1
  fi
  # shellcheck disable=SC2016 # git submodule foreach expands $displaypath itself
  if ! git -C "${dir}" submodule --quiet foreach --recursive 'printf "%s\0" "$displaypath"' >"${submodules}"; then
    rm -f "${scan}" "${submodules}"
    secrets_guard_error "Enumerating submodules of ${dir} failed, so the secrets guard cannot scan them; path: copies submodule working trees whole."
    return 1
  fi
  # sub_fail rather than a cleanup inside the loop, for the reason the ${scan}
  # reads use one: the redirect below is reading the file the cleanup removes.
  # break leaves the loop status 0, which keeps a reported failure apart from a
  # read that stopped on its own.
  local sub_read_rc=0 sub_fail=0
  while IFS= read -r -d '' sub; do
    [[ -n ${sub} ]] || continue
    # The two scans are not scoped alike. ls-files above is confined to ${dir},
    # while foreach walks the whole superproject and reports what sits outside
    # it as ../<path>, which reaching a subdirectory needs only the root
    # .gitignore to lack the block while ${dir}/.gitignore carries it. Those
    # trees are not copied by path:${dir}, so scanning them can only abort on a
    # file this reference never discloses, with --allow-secret-copy the sole way
    # past. A submodule under ${dir} keeps a forward path and is still scanned.
    if [[ ${sub} == ../* ]]; then
      continue
    fi
    if ! git -C "${dir}/${sub}" ls-files --others -z >"${scan}"; then
      secrets_guard_error "Listing untracked files in submodule ${sub} failed, so the secrets guard cannot scan it; path: copies its working tree whole."
      sub_fail=1
      break
    fi
    # The same boundary one level down: a stray repository nested in the
    # submodule's own untracked tree stops ls-files there too. foreach walks
    # registered submodules, so this pass reaches those and not these.
    read_rc=0
    emit_rc=0
    while IFS= read -r -d '' subfile; do
      if [[ ${subfile} == */ ]] || secrets_guard_is_hit "${sub}/${subfile}"; then
        if ! secrets_guard_emit "${sub}/${subfile}" "submodule ${sub} of ${dir}"; then
          emit_rc=1
          break
        fi
      fi
    done <"${scan}" || read_rc=$?
    if [[ ${emit_rc} -ne 0 ]]; then
      sub_fail=1
      break
    fi
    # No case in tests/secrets-guard/run.sh covers this one, and dropping it is
    # the single mutation the suite does not catch. Both passes read the one
    # ${scan} file, so any lever that makes it unreadable stops the top-level
    # read first; only something changing it between the passes reaches here,
    # which is the same race that put the check on the read above. It stays
    # because a per-submodule temp file would reopen the hole in silence.
    if [[ ${read_rc} -ne 0 ]]; then
      secrets_guard_error "Reading the untracked listing of submodule ${sub} back failed, so the secrets guard classified none of what it listed there. Check the filesystem holding TMPDIR, or pass --allow-secret-copy to continue anyway."
      sub_fail=1
      break
    fi
  done <"${submodules}" || sub_read_rc=$?
  if [[ ${sub_fail} -ne 0 ]]; then
    rm -f "${scan}" "${submodules}"
    return 1
  fi
  if [[ ${sub_read_rc} -ne 0 ]]; then
    rm -f "${scan}" "${submodules}"
    secrets_guard_error "Reading the submodule list of ${dir} back failed, so the secrets guard scanned none of what it enumerated. Check the filesystem holding TMPDIR, or pass --allow-secret-copy to continue anyway."
    return 1
  fi
  rm -f "${scan}" "${submodules}"
  # Explicit, because the cleanup above would otherwise be this function's exit
  # status: a failed rm made a completed scan read as one that could not run,
  # and the caller threw away the hit list it had already written. Leaving a
  # temp file behind is not a reason to stop reporting secrets.
  return 0
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
  # Every external the guard runs, gated once and ahead of everything, because
  # not one of them reports itself usefully from where it runs.
  #
  # git is the reason this is a loop and not a chain of local checks: a missing
  # one used to share a condition with the not-a-worktree skip below and return
  # 0, which is the single fail-open this control exists to prevent.
  # flake_path_ref_reason consults no git, so --allow-dirty still selects path:
  # and the copy still happens, while the notice tells the operator their git
  # worktree is not one. grep not found returns 127, which negates to true and
  # skips the discriminator. awk builds the deny list, so a missing one empties
  # it and the parser reports .gitignore drift that has not happened. mktemp
  # leaves the temp paths empty, and the failure then surfaces as a redirect
  # error against a git call that never ran. rm closes secrets_guard_paths, so
  # its 127 became that function's status and discarded a completed hit list.
  #
  # command -v answers presence, not operability, so it is the floor and not the
  # whole check: each mktemp call tests its own status as well, since a present
  # one still fails on a read-only TMPDIR and lands in the same two places.
  local tool
  for tool in git grep awk mktemp rm; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      secrets_guard_error "${tool} was not found, so the secrets guard cannot run. Put it on PATH, or pass --allow-secret-copy to continue anyway."
      return 2
    fi
  done
  # Without this, --flake-dir pointed at a flake that is not a git worktree
  # reaches the missing-.gitignore abort below and is told to run write-files,
  # which does not own that directory. No git worktree means no ignore set, so
  # there is nothing for path: to smuggle past .gitignore.
  if ! git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # rev-parse answers 128 for a repository git declines to open as well as for
    # a directory that is not one, and only the second has no ignore set to
    # smuggle anything past. A .git marker separates them, and it is the marker
    # flake_path_ref_reason selects path: on, so reading both as "not a worktree"
    # disables the guard on exactly the reference that makes the copy: a linked
    # worktree outlives the gitdir its .git file points at. -L keeps a dangling
    # symlink in the marker class, which -e alone drops. Dubious ownership
    # arrives here on a tree git reads perfectly well, so safe.directory is named
    # beside the other two remedies.
    if [[ -e "${dir}/.git" || -L "${dir}/.git" ]]; then
      secrets_guard_error "${dir} carries a .git marker but git will not open it as a repository, so the secrets guard cannot read what path: would add over the tracked tree. Repair the repository, add it to safe.directory when the tree belongs to another user, or pass --allow-secret-copy to continue anyway."
      return 2
    fi
    secrets_guard_notice "${dir} is not a git worktree; nothing defines an ignore set, so the secrets scan does not run."
    return 0
  fi
  # rev-parse answers yes from any subdirectory of a worktree, while every
  # .gitignore this file reads is ${dir}/.gitignore. A flake one level down from
  # a root that carries the block therefore found no file, took the "never had
  # one" skip below and returned 0 while path: copied its untracked .env and
  # id_* into the store, with a notice saying the tree defines no patterns for
  # them when it defines them one directory up.
  #
  # A subdirectory carrying its own block falls through, since the reads below
  # then resolve to the file that does define its ignore set. Everything else
  # one level down takes its ignore set from the root, so the root is what gets
  # classified, with the same three questions the discriminators below ask of
  # ${dir}: those resolve their pathspecs against ${dir}, which one level down
  # asks about sub/.gitignore and sub/modules/development/gitignore.nix, so
  # every drift state above returned "foreign tree" and skipped. Only a root
  # that is genuinely foreign, no block and no generator, still skips: the block
  # is this repo's convention, and aborting a tree that never had one names a
  # module it does not contain.
  #
  # pwd -P because rev-parse resolves symlinks and the comparison has to. Both
  # callers already absolutise the same way, so this only covers a third one.
  local toplevel resolved
  if ! toplevel="$(git -C "${dir}" rev-parse --show-toplevel 2>/dev/null)"; then
    secrets_guard_error "Resolving the worktree root of ${dir} failed, so the secrets guard cannot tell it from a subdirectory whose ignore set lives above it. Repair the repository, or pass --allow-secret-copy to continue anyway."
    return 2
  fi
  if ! resolved="$(cd "${dir}" 2>/dev/null && pwd -P)"; then
    secrets_guard_error "Resolving ${dir} to an absolute path failed, so the secrets guard cannot tell it from a subdirectory whose ignore set lives above it. Check that it is a readable directory, or pass --allow-secret-copy to continue anyway."
    return 2
  fi
  if [[ ${resolved} != "${toplevel}" ]]; then
    # The subdirectory's own block is asked about first, because it is the file
    # the reads below would resolve to and it defines exactly the patterns the
    # scan needs. Aborting there would refuse a directory the guard can answer
    # for, and send its operator to a root whose tree path:${dir} does not copy.
    local dir_heading_rc=1
    if [[ -f "${dir}/.gitignore" ]]; then
      dir_heading_rc=0
      grep -qxF '# Secrets safety (defense-in-depth)' "${dir}/.gitignore" || dir_heading_rc=$?
      if [[ ${dir_heading_rc} -gt 1 ]]; then
        secrets_guard_error "Reading ${dir}/.gitignore failed (grep exit ${dir_heading_rc}), so the secrets guard cannot tell whether it defines a secrets block of its own. Fix its permissions, or pass --allow-secret-copy to continue anyway."
        return 2
      fi
    fi
    if [[ ${dir_heading_rc} -ne 0 ]]; then
      if [[ -f "${toplevel}/.gitignore" ]]; then
        local root_heading_rc=0
        grep -qxF '# Secrets safety (defense-in-depth)' "${toplevel}/.gitignore" || root_heading_rc=$?
        if [[ ${root_heading_rc} -gt 1 ]]; then
          secrets_guard_error "Reading ${toplevel}/.gitignore failed (grep exit ${root_heading_rc}), so the secrets guard cannot tell whether the root of ${dir}'s worktree defines a secrets block for it. Fix its permissions, or pass --allow-secret-copy to continue anyway."
          return 2
        fi
        if [[ ${root_heading_rc} -eq 0 ]]; then
          secrets_guard_error "${dir} is a subdirectory of the worktree at ${toplevel}, whose .gitignore carries the secrets block that covers what path:${dir} would copy, and this guard reads ${dir}/.gitignore only. Point the flake directory at ${toplevel}, or pass --allow-secret-copy to continue anyway."
          return 2
        fi
        # No heading at the root either. Drift there is a block that covered
        # ${dir} and stopped, so the generator decides, and it is asked of the
        # root: ${dir} never tracks modules/development/gitignore.nix, which is
        # what read every drift above as a foreign tree.
        local root_generator_rc=0
        secrets_guard_tracked "${toplevel}" modules/development/gitignore.nix || root_generator_rc=$?
        if [[ ${root_generator_rc} -gt 1 ]]; then
          secrets_guard_error "Checking whether the worktree root ${toplevel} tracks modules/development/gitignore.nix failed (git exit ${root_generator_rc}), so the secrets guard cannot tell drift above ${dir} from a foreign tree."
          return 2
        fi
        if [[ ${root_generator_rc} -eq 0 ]]; then
          secrets_guard_error "${toplevel}/.gitignore has no secrets block while that tree owns modules/development/gitignore.nix, and ${dir} is a subdirectory of it, so the ignore set covering what path:${dir} would copy has drifted away. Realign that generator and run write-files, or pass --allow-secret-copy to continue anyway."
          return 2
        fi
      else
        # Absent at the root. Tracked-but-absent is the state the generator
        # produces, and it is the drift the branch below aborts on one directory
        # up; a root that never had one is the foreign tree that still skips.
        local root_gitignore_rc=0
        secrets_guard_tracked "${toplevel}" .gitignore || root_gitignore_rc=$?
        if [[ ${root_gitignore_rc} -gt 1 ]]; then
          secrets_guard_error "Checking whether the worktree root ${toplevel} tracks .gitignore failed (git exit ${root_gitignore_rc}), so the secrets guard cannot tell drift above ${dir} from a tree that never had one."
          return 2
        fi
        if [[ ${root_gitignore_rc} -eq 0 ]]; then
          secrets_guard_error "${toplevel}/.gitignore is tracked but absent from the worktree and ${dir} is a subdirectory of it, so the secrets guard cannot read the ignore set that covers what path:${dir} would copy. Restore it with write-files, or pass --allow-secret-copy to continue anyway."
          return 2
        fi
      fi
    fi
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
  # The same discriminator one level down. The block is this repo's convention,
  # emitted by modules/development/gitignore.nix, and practically every other
  # repository has a .gitignore without it; aborting there would name a module
  # that tree does not contain. A renamed or thinned heading in a tree that does
  # own the generator still fails closed in the parser.
  # grep answers three ways as well: 0 match, 1 no match, 2 could not read it.
  # The -f above is true for a file the process cannot open, so folding 2 into
  # "no heading" sends a foreign tree to the skip below and returns 0 with path:
  # already selected, and sends a tree that owns the generator to the parser,
  # which then reports drift in a block it never managed to read.
  local heading_rc=0
  grep -qxF '# Secrets safety (defense-in-depth)' "${dir}/.gitignore" || heading_rc=$?
  if [[ ${heading_rc} -gt 1 ]]; then
    secrets_guard_error "Reading ${dir}/.gitignore failed (grep exit ${heading_rc}), so the secrets guard cannot tell a missing secrets block from a file it could not read. Fix its permissions, or pass --allow-secret-copy to continue anyway."
    return 2
  fi
  if [[ ${heading_rc} -eq 1 ]]; then
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
  # Same check as the scan's own mktemp, and this one had no message at all: an
  # empty hits_file made the call below fail on its redirect, which `if !`
  # inverted into the abort, so the run returned 2 having printed nothing the
  # guard wrote. Both callers suspend errexit around this function, so the empty
  # assignment could not surface as an ERR trap either.
  local hits_file
  if ! hits_file="$(mktemp)"; then
    secrets_guard_error "Creating a temporary file for the hit list failed (TMPDIR=${TMPDIR:-/tmp}), so the secrets guard cannot run. Point TMPDIR at a writable filesystem, or pass --allow-secret-copy to continue anyway."
    return 2
  fi
  if ! secrets_guard_paths "${dir}" >"${hits_file}"; then
    rm -f "${hits_file}"
    return 2
  fi
  # Read side of the same round trip, and the last consumer of that file with no
  # status read. secrets_guard_paths has already returned by here, so its 0 says
  # the scan completed and not that the file it wrote is still readable: a
  # redirect that cannot open it leaves hit_list at its initialised zero length,
  # which the check below reads as a clear tree. An empty but readable file is
  # status 0, so the legitimate clean tree still passes through here.
  local -a hit_list=()
  if ! mapfile -d '' -t hit_list <"${hits_file}"; then
    rm -f "${hits_file}"
    secrets_guard_error "Reading the hit list back from ${hits_file} failed, so the secrets guard cannot report what ${copier} would copy. Check the filesystem holding TMPDIR, or pass --allow-secret-copy to continue anyway."
    return 2
  fi
  rm -f "${hits_file}"
  if [[ ${#hit_list[@]} -eq 0 ]]; then
    return 0
  fi

  secrets_guard_error "Untracked paths that ${copier} would copy into the world-readable store, which the git+file fetcher would have left behind, either matching the .gitignore secrets block or impossible to scan. Submodule working trees are scanned too, with the same patterns, since path: copies them whole."
  # git check-ignore is the obvious way to confirm a hit, and it disagrees for
  # any pattern the block anchors to a subdirectory, so say why before the list
  # rather than let the operator read the disagreement as a false positive.
  printf 'A pattern the block anchors to a subdirectory is matched by name here, so git check-ignore will not confirm every hit: the anchor scopes git ignore rules, not this scan.\n' >&2
  # One binding for the cap, since the notice below and the tally both describe
  # the slice that gets printed rather than everything that was found.
  local shown=50
  # Name the second basis once rather than per entry, and only when the printed
  # slice holds one: an operator who reads every hit as a pattern match goes
  # looking for the pattern a directory name never matched, and a marker
  # explained past the cap appears nowhere in the output at all.
  local hit
  for hit in "${hit_list[@]:0:shown}"; do
    if [[ ${hit} == */ ]]; then
      printf 'A trailing slash marks an untracked directory that is itself a git repository. ls-files stops at one, so nothing inside it was compared against the block, while path: copies it whole.\n' >&2
      break
    fi
  done
  # Report the truncation. The next line asks for all of them to be moved, so a
  # silent cap reads as a complete list and sends the operator back into the
  # same abort with no idea how much is left.
  # %q, not %s: the list is NUL delimited so a path holding a newline stays one
  # element, and %s would split it back into two lines here, moving the
  # ambiguity from the tally to the listing. Ordinary paths render unchanged.
  printf '%q\n' "${hit_list[@]:0:shown}" >&2
  if [[ ${#hit_list[@]} -gt ${shown} ]]; then
    printf '... and %d more not shown.\n' "$((${#hit_list[@]} - shown))" >&2
  fi
  printf "Move them outside the worktree, or pass --allow-secret-copy (ALLOW_SECRET_COPY=1) to override.\n" >&2
  return 1
}
