#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

prog_name="${0##*/}"

usage() {
  cat <<EOF
usage: ${prog_name} <fork-clone-path>

Install the canonical sync-upstream GitHub workflow into a fork clone and
push it to the clone's current branch. The workflow merges the same-named
upstream branch into the fork branch every 8 hours through the GitHub
merge-upstream API; a merge conflict fails the run instead of rewriting
history. The script verifies the fork relationship, requires the current
branch to be the fork default branch, enables GitHub Actions when disabled,
and dispatches a verification run.

See docs/reference/fork-sync-automation.md for behavior and recovery.
EOF
}

error_msg() {
  printf '%s: %s\n' "${prog_name}" "$1" >&2
}

die() {
  error_msg "$1"
  exit 1
}

workflow_rel_path=".github/workflows/sync-upstream.yml"
workflow_file_name="sync-upstream.yml"

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
-h | --help)
  usage
  exit 0
  ;;
esac

clone_path="$1"

command -v gh >/dev/null 2>&1 || die 'gh is required'

git -C "${clone_path}" rev-parse --show-toplevel >/dev/null 2>&1 ||
  die "not a git worktree: ${clone_path}"
branch="$(git -C "${clone_path}" symbolic-ref --quiet --short HEAD)" ||
  die 'not on a branch'
origin_url="$(git -C "${clone_path}" remote get-url origin 2>/dev/null)" ||
  die 'no origin remote found'

repo="${origin_url%.git}"
repo="${repo#https://github.com/}"
repo="${repo#ssh://git@github.com/}"
repo="${repo#git@github.com:}"
if [[ ${repo} == *://* || ${repo} == *@* || ${repo} != */* ]]; then
  die "origin is not a GitHub repository: ${origin_url}"
fi

parent="$(gh api "repos/${repo}" --jq '.parent.full_name // empty')"
[[ -n ${parent} ]] || die "${repo} has no fork parent, so the merge-upstream API cannot work"

default_branch="$(gh api "repos/${repo}" --jq .default_branch)"
if [[ ${branch} != "${default_branch}" ]]; then
  die "current branch ${branch} is not the default branch ${default_branch}; scheduled workflows fire only from the default branch"
fi

if [[ "$(gh api "repos/${repo}/actions/permissions" --jq .enabled)" != "true" ]]; then
  gh api --method PUT "repos/${repo}/actions/permissions" \
    -F enabled=true -f allowed_actions=all >/dev/null
  printf 'Enabled GitHub Actions on %s\n' "${repo}"
fi

git -C "${clone_path}" pull --ff-only origin "${branch}"

mkdir -p "${clone_path}/.github/workflows"
cat >"${clone_path}/${workflow_rel_path}" <<'EOF'
---
name: Sync Fork With Upstream
"on":
  schedule:
    - cron: "17 */8 * * *" # Every 8 hours, offset from :00 scheduler congestion
  workflow_dispatch: # Allow manual trigger

permissions:
  contents: write

concurrency:
  group: sync-upstream
  cancel-in-progress: false

jobs:
  sync:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Merge upstream into this branch
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          BRANCH: ${{ github.ref_name }}
        run: |
          # Server-side merge of the same-named branch from the parent
          # repository. A merge conflict fails the run with HTTP 409 instead
          # of rewriting history; resolve locally with git-fork-sync.
          before="$(gh api "repos/${REPO}/branches/${BRANCH}" --jq .commit.sha)"
          gh api --method POST "repos/${REPO}/merge-upstream" -f "branch=${BRANCH}" | tee /tmp/sync-result.json
          after="$(gh api "repos/${REPO}/branches/${BRANCH}" --jq .commit.sha)"
          {
            echo "## Upstream sync: ${BRANCH}"
            echo "- result: $(jq -r '.merge_type' /tmp/sync-result.json)"
            echo "- message: $(jq -r '.message' /tmp/sync-result.json)"
            echo "- before: ${before}"
            echo "- after: ${after}"
          } >>"$GITHUB_STEP_SUMMARY"
EOF

tracked=false
if git -C "${clone_path}" ls-files --error-unmatch "${workflow_rel_path}" >/dev/null 2>&1; then
  tracked=true
fi

if [[ ${tracked} == true ]] && git -C "${clone_path}" diff --quiet HEAD -- "${workflow_rel_path}"; then
  printf '%s already current on %s:%s\n' "${workflow_rel_path}" "${repo}" "${branch}"
else
  git -C "${clone_path}" add "${workflow_rel_path}"
  git -C "${clone_path}" commit \
    -m 'ci: add scheduled upstream sync workflow' \
    -m 'Replaces the manual git-fork-sync cadence for this fork. The job calls
POST /repos/{owner}/{repo}/merge-upstream every 8 hours to merge the
same-named upstream branch server side. A merge conflict fails the run with
HTTP 409 instead of rewriting history, so recovery stays manual via
git-fork-sync. The target branch is the fork default branch because
scheduled workflows fire only from the default branch.

Validation: nix run nixpkgs#actionlint -- .github/workflows/sync-upstream.yml'
  git -C "${clone_path}" push origin "${branch}"
fi

for _ in 1 2 3 4 5; do
  if gh workflow run "${workflow_file_name}" -R "${repo}" --ref "${branch}" 2>/dev/null; then
    printf 'Dispatched verification run. Watch with: gh run list --workflow=%s -R %s\n' \
      "${workflow_file_name}" "${repo}"
    exit 0
  fi
  sleep 3
done
die "workflow ${workflow_file_name} was pushed but could not be dispatched; check: gh workflow list --all -R ${repo}"
