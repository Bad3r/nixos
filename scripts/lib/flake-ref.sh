# shellcheck shell=bash
# Sourced by build.sh and scripts/cache-coverage.sh. Not executable on its own.
#
# One copy of "which reference does this tree get". build.sh derives three
# things from it, the installable it builds, the notice that explains the
# missing system.configurationRevision, and the gate on the secrets guard, and
# scripts/cache-coverage.sh has to reach the same answer or it measures a tree
# the build would not build. Hand-kept copies already drifted once: before
# 65e8afbe the report hardcoded path: and copied unguarded on every run, and the
# repair was a special case in build.sh that a second repair then deleted.
#
# The two reasons are separate because they cost different things, but neither
# caller branches on which: both are here so the notice can name the one that
# applied.

# flake_path_ref_reason DIR ALLOW_DIRTY
#
# Prints "allow-dirty" or "linked worktree" when DIR needs a path: reference,
# and nothing when the bare ref stays. DIR must already be absolute: a relative
# one reaches Lix as `path:relative/dir`, whose fetcher throws when it writes
# flake.lock back, so both callers resolve their directory argument first.
#
# path: is what makes untracked files reachable, which git+file ignores, and it
# is the only form that works in a linked worktree, where .git is a file and Lix
# reads it as a directory. Elsewhere the bare ref stays: path: dumps the tree
# unfiltered, so a primary checkout would copy the whole .git directory into the
# store and lose self.rev with it.
flake_path_ref_reason() {
  local dir="$1"
  local allow_dirty="$2"
  if [[ ${allow_dirty} == "true" || ${allow_dirty} == "1" ]]; then
    printf 'allow-dirty'
  elif [[ -f "${dir}/.git" ]]; then
    printf 'linked worktree'
  fi
}
