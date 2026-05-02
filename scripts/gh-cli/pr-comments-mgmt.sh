#!/usr/bin/env bash
# shellcheck disable=SC2016 # GraphQL queries use $vars as GraphQL variables, not shell vars
# pr-comments-mgmt.sh: resolve and/or minimize PR review threads via GitHub GraphQL.

set -Eeuo pipefail

PROG_NAME="${0##*/}"
QUIET=false
REASON="OUTDATED"

readonly VALID_REASONS=("OUTDATED" "RESOLVED" "OFF_TOPIC" "SPAM" "ABUSE" "DUPLICATE")

if ! command -v jq >/dev/null 2>&1; then
  printf 'pr-comments-mgmt.sh: required command not found: jq\n' >&2
  exit 1
fi

_json_string() {
  # Emit "$1" as a JSON string literal (with surrounding quotes). Delegates
  # to jq so the full U+0000-U+001F control-character range and surrogate
  # pairs are escaped per RFC 8259 §7, instead of only the named escapes.
  jq -Rn --arg s "$1" '$s'
}

err() {
  printf '{"level":"error","prog":%s,"message":%s}\n' \
    "$(_json_string "${PROG_NAME}")" "$(_json_string "$*")" >&2
}

trap 'err "fatal: line ${LINENO} (exit $?): ${BASH_COMMAND}"' ERR

log() {
  [[ ${QUIET} == true ]] && return 0
  printf '{"level":"info","prog":%s,"message":%s}\n' \
    "$(_json_string "${PROG_NAME}")" "$(_json_string "$*")" >&2
}

die() {
  local code=$1
  shift
  err "$*"
  exit "${code}"
}

usage() {
  cat <<'USAGE'
pr-comments-mgmt.sh: resolve and/or minimize PR review threads via GitHub GraphQL.

A helper with strict mode, that uses the GitHub GraphQL API (`gh api graphql`) to:
  * resolveReviewThread: close a review thread
  * minimizeComment: hide a comment as OUTDATED (or another classifier)

Subcommands:
  resolve <thread-id>...                   Resolve one or more threads.
  hide-comment <comment-node-id>...        Minimize comments as OUTDATED.
  hide-thread <thread-id>...               Minimize every comment in the thread
                                           then resolve it.
  list-threads [<owner/repo>] [<pr-number>]
                                           Print thread IDs (+ resolution and
                                           comment node IDs) as JSON. With no
                                           args, defaults to current repo and
                                           PR via gh; with one numeric arg,
                                           uses it as the PR number for the
                                           current repo.
  current-pr                               Print the open PR for the current
                                           repo/branch as JSON (number, title,
                                           body, and labels as a name array).
                                           Exits non-zero if no open PR is
                                           found.

Options:
  --reason {OUTDATED|RESOLVED|OFF_TOPIC|SPAM|ABUSE|DUPLICATE}
                                           Classifier for hide* (default: OUTDATED).
  --quiet                                  Suppress per-action output.
  -h, --help                               Show this message.

Exit codes:
  0   success
  1   user error (bad args, missing prerequisites)
  2   API error

Examples:
  pr-comments-mgmt.sh resolve PRRT_kwDOPeLwm85_EPVC
  pr-comments-mgmt.sh hide-thread --reason OUTDATED PRRT_kwDOPeLwm85_EQHI PRRT_kwDOPeLwm85_EQsI
  pr-comments-mgmt.sh list-threads
  pr-comments-mgmt.sh list-threads 123
  pr-comments-mgmt.sh list-threads owner/repo 123
  pr-comments-mgmt.sh current-pr
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die 1 "required command not found: $1"
}

_gh_run() {
  # Run "gh $@", capturing gh's stderr and re-emitting it via err on failure
  # so callers stay in JSON-only output mode. gh's stdout passes through to
  # this function's stdout. Returns gh's exit code.
  local _rc=0 _stderr
  exec 4>&1
  _stderr=$(gh "$@" 2>&1 1>&4) || _rc=$?
  exec 4>&-
  if ((_rc != 0)) && [[ -n ${_stderr} ]]; then
    err "gh ${1:-?}: ${_stderr}"
  fi
  return "${_rc}"
}

valid_reason() {
  local candidate="$1"
  local r
  for r in "${VALID_REASONS[@]}"; do
    [[ ${candidate} == "${r}" ]] && return 0
  done
  return 1
}

graphql_call() {
  # Args: <query> <field=value>... -> echoes JSON body to stdout, returns exit code.
  # Inspects the response for top-level GraphQL `errors` and fails with code 2 if present,
  # so partial errors (data populated alongside errors) are never silently swallowed.
  local query="$1"
  shift

  # Use `-F` so numeric/boolean values are typed correctly (Int/Boolean/null);
  # GraphQL Int! variables like `$number` reject quoted strings sent via `-f`.
  local args=()
  for kv in "$@"; do
    args+=(-F "${kv}")
  done

  local response
  if ! response=$(_gh_run api graphql -f query="${query}" "${args[@]}"); then
    return 2
  fi

  local errors
  errors=$(printf '%s' "${response}" | jq -c '(.errors // []) | select(length > 0)')
  if [[ -n ${errors} ]]; then
    err "graphql errors: ${errors}"
    return 2
  fi

  printf '%s' "${response}"
}

resolve_thread() {
  local thread_id="$1"
  [[ -n ${thread_id} ]] || die 1 "resolve: empty thread id"

  local response
  if ! response=$(graphql_call '
mutation($id: ID!) {
  resolveReviewThread(input: { threadId: $id }) {
    thread { id isResolved }
  }
}
' "id=${thread_id}"); then
    err "resolve: graphql call failed for ${thread_id}"
    return 2
  fi

  local resolved
  resolved=$(printf '%s' "${response}" | jq -r '.data.resolveReviewThread.thread.isResolved // "null"')

  case "${resolved}" in
  true) log "resolved: ${thread_id}" ;;
  null)
    err "resolve: unexpected response for ${thread_id}: ${response}"
    return 2
    ;;
  *)
    err "resolve: ${thread_id} reported isResolved=${resolved}"
    return 2
    ;;
  esac
}

minimize_comment() {
  local node_id="$1"
  local classifier="$2"
  [[ -n ${node_id} ]] || die 1 "hide: empty comment node id"

  local response
  if ! response=$(graphql_call '
mutation($id: ID!, $classifier: ReportedContentClassifiers!) {
  minimizeComment(input: { subjectId: $id, classifier: $classifier }) {
    minimizedComment { isMinimized minimizedReason }
  }
}
' "id=${node_id}" "classifier=${classifier}"); then
    err "hide: graphql call failed for ${node_id}"
    return 2
  fi

  local is_min
  is_min=$(printf '%s' "${response}" | jq -r '.data.minimizeComment.minimizedComment.isMinimized // "null"')

  if [[ ${is_min} != "true" ]]; then
    err "hide: unexpected response for ${node_id}: ${response}"
    return 2
  fi

  log "hidden (${classifier}): ${node_id}"
}

hide_thread() {
  local thread_id="$1"
  local classifier="$2"
  [[ -n ${thread_id} ]] || die 1 "hide-thread: empty thread id"

  local cursor="null"
  local validated=false
  while :; do
    local response
    if ! response=$(graphql_call '
query($id: ID!, $cursor: String) {
  node(id: $id) {
    __typename
    ... on PullRequestReviewThread {
      comments(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { id isMinimized }
      }
    }
  }
}
' "id=${thread_id}" "cursor=${cursor}"); then
      err "hide-thread: graphql lookup failed for ${thread_id}"
      return 2
    fi

    if [[ ${validated} == false ]]; then
      local typename
      typename=$(printf '%s' "${response}" | jq -r '.data.node.__typename // ""')
      if [[ ${typename} != "PullRequestReviewThread" ]]; then
        err "hide-thread: ${thread_id} is ${typename:-not found}, expected PullRequestReviewThread"
        return 2
      fi
      validated=true
    fi

    local cid
    while IFS= read -r cid; do
      [[ -z ${cid} ]] && continue
      minimize_comment "${cid}" "${classifier}" || return $?
    done < <(printf '%s' "${response}" |
      jq -r '.data.node.comments.nodes[] | select(.isMinimized | not) | .id')

    local has_next
    has_next=$(printf '%s' "${response}" | jq -r '.data.node.comments.pageInfo.hasNextPage')
    [[ ${has_next} == "true" ]] || break
    cursor=$(printf '%s' "${response}" | jq -r '.data.node.comments.pageInfo.endCursor')
  done

  # resolveReviewThread is idempotent on GitHub's side, so no TOCTOU short-circuit.
  resolve_thread "${thread_id}"
}

_fetch_thread_comments_page() {
  # Echoes the comments page JSON for a thread at the given cursor (use "null" for first page).
  local thread_id="$1"
  local cursor="$2"
  graphql_call '
query($id: ID!, $cursor: String) {
  node(id: $id) {
    ... on PullRequestReviewThread {
      comments(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { id databaseId author { login } isMinimized minimizedReason }
      }
    }
  }
}
' "id=${thread_id}" "cursor=${cursor}"
}

_paginate_thread_comments() {
  # Reads a thread node JSON on stdin, fetches any remaining comment pages,
  # and emits the thread node JSON (with comments.nodes fully populated) on stdout.
  local thread
  thread=$(cat)

  local thread_id
  thread_id=$(printf '%s' "${thread}" | jq -r '.id')

  local has_next
  has_next=$(printf '%s' "${thread}" | jq -r '.comments.pageInfo.hasNextPage')

  local cursor
  cursor=$(printf '%s' "${thread}" | jq -r '.comments.pageInfo.endCursor')

  while [[ ${has_next} == "true" ]]; do
    local page
    if ! page=$(_fetch_thread_comments_page "${thread_id}" "${cursor}"); then
      err "list-threads: failed to fetch comments page for ${thread_id}"
      return 2
    fi

    thread=$(jq -n --argjson t "${thread}" --argjson p "${page}" '
      $t | .comments.nodes += $p.data.node.comments.nodes
         | .comments.pageInfo = $p.data.node.comments.pageInfo
    ')

    has_next=$(printf '%s' "${thread}" | jq -r '.comments.pageInfo.hasNextPage')
    cursor=$(printf '%s' "${thread}" | jq -r '.comments.pageInfo.endCursor')
  done

  printf '%s' "${thread}"
}

list_threads() {
  local owner_repo="$1"
  local pr_number="$2"
  [[ ${owner_repo} == */* ]] || die 1 "list-threads: expected <owner/repo>, got '${owner_repo}'"
  [[ ${pr_number} =~ ^[0-9]+$ ]] || die 1 "list-threads: expected numeric pr number, got '${pr_number}'"

  local owner=${owner_repo%/*}
  local repo=${owner_repo#*/}

  local cursor="null"
  local all_threads='[]'

  while :; do
    local response
    if ! response=$(graphql_call '
query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 100) {
            pageInfo { hasNextPage endCursor }
            nodes { id databaseId author { login } isMinimized minimizedReason }
          }
        }
      }
    }
  }
}
' "owner=${owner}" "repo=${repo}" "number=${pr_number}" "cursor=${cursor}"); then
      err "list-threads: graphql call failed"
      return 2
    fi

    if ! printf '%s' "${response}" | jq -e '.data.repository.pullRequest' >/dev/null; then
      err "list-threads: ${owner}/${repo} pull request #${pr_number} not found"
      return 2
    fi

    local page
    page=$(printf '%s' "${response}" | jq '.data.repository.pullRequest.reviewThreads.nodes')

    # Find thread indices whose inner comments span more than one page in a
    # single jq pass, then merge follow-up pages only for those entries.
    local needs=()
    mapfile -t needs < <(printf '%s' "${page}" |
      jq -r 'to_entries[] | select(.value.comments.pageInfo.hasNextPage) | .key')
    local idx
    for idx in "${needs[@]}"; do
      local thread_in thread_out
      thread_in=$(printf '%s' "${page}" | jq ".[${idx}]")
      if ! thread_out=$(printf '%s' "${thread_in}" | _paginate_thread_comments); then
        return 2
      fi
      page=$(jq -n --argjson p "${page}" --argjson t "${thread_out}" --argjson i "${idx}" \
        '$p | .[$i] = $t')
    done

    all_threads=$(jq -n --argjson a "${all_threads}" --argjson b "${page}" '$a + $b')

    local page_info has_next
    page_info=$(printf '%s' "${response}" |
      jq -c '.data.repository.pullRequest.reviewThreads.pageInfo')
    has_next=$(printf '%s' "${page_info}" | jq -r '.hasNextPage')
    [[ ${has_next} == "true" ]] || break
    cursor=$(printf '%s' "${page_info}" | jq -r '.endCursor')
  done

  printf '%s' "${all_threads}" | jq '.'
}

current_pr() {
  local data
  if ! data=$(_gh_run pr view --json number,title,body,labels,state); then
    err "current-pr: no PR found for current branch"
    return 1
  fi

  local state
  state=$(printf '%s' "${data}" | jq -r '.state')
  if [[ ${state} != "OPEN" ]]; then
    err "current-pr: PR for current branch is ${state}, expected OPEN"
    return 1
  fi

  printf '%s' "${data}" | jq 'del(.state) | .labels |= map(.name)'
}

main() {
  require_cmd gh

  local positional=()
  local reason_set=false
  while (($# > 0)); do
    case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    --reason)
      [[ -n ${2:-} ]] || die 1 "--reason requires a value"
      valid_reason "$2" || die 1 "--reason must be one of: ${VALID_REASONS[*]}"
      REASON="$2"
      reason_set=true
      shift 2
      ;;
    --reason=*)
      local rv="${1#--reason=}"
      valid_reason "${rv}" || die 1 "--reason must be one of: ${VALID_REASONS[*]}"
      REASON="${rv}"
      reason_set=true
      shift
      ;;
    --)
      shift
      positional+=("$@")
      break
      ;;
    -*)
      die 1 "unknown option: $1"
      ;;
    *)
      positional+=("$1")
      shift
      ;;
    esac
  done

  ((${#positional[@]} > 0)) || {
    usage >&2
    exit 1
  }

  local subcommand="${positional[0]}"
  local args=("${positional[@]:1}")

  case "${subcommand}" in
  resolve)
    [[ ${reason_set} == true ]] && die 1 "resolve: --reason is not applicable"
    ((${#args[@]} > 0)) || die 1 "resolve: need at least one thread id"
    local id rc=0
    for id in "${args[@]}"; do
      resolve_thread "${id}" || rc=$?
    done
    exit "${rc}"
    ;;
  hide-comment)
    ((${#args[@]} > 0)) || die 1 "hide-comment: need at least one comment node id"
    local id rc=0
    for id in "${args[@]}"; do
      minimize_comment "${id}" "${REASON}" || rc=$?
    done
    exit "${rc}"
    ;;
  hide-thread)
    ((${#args[@]} > 0)) || die 1 "hide-thread: need at least one thread id"
    local id rc=0
    for id in "${args[@]}"; do
      hide_thread "${id}" "${REASON}" || rc=$?
    done
    exit "${rc}"
    ;;
  current-pr)
    [[ ${reason_set} == true ]] && die 1 "current-pr: --reason is not applicable"
    ((${#args[@]} == 0)) || die 1 "current-pr: takes no arguments"
    current_pr || exit $?
    ;;
  list-threads)
    [[ ${reason_set} == true ]] && die 1 "list-threads: --reason is not applicable"
    local owner_repo pr_number
    case "${#args[@]}" in
    0)
      owner_repo=$(_gh_run repo view --json nameWithOwner -q .nameWithOwner) ||
        die 1 "list-threads: failed to detect current repo via gh"
      local pr_view
      pr_view=$(_gh_run pr view --json number,state) ||
        die 1 "list-threads: failed to detect current PR via gh"
      [[ $(printf '%s' "${pr_view}" | jq -r '.state') == "OPEN" ]] ||
        die 1 "list-threads: PR for current branch is $(printf '%s' "${pr_view}" | jq -r '.state'), expected OPEN"
      pr_number=$(printf '%s' "${pr_view}" | jq -r '.number')
      ;;
    1)
      [[ ${args[0]} =~ ^[0-9]+$ ]] ||
        die 1 "list-threads: single arg must be a PR number; got '${args[0]}'"
      owner_repo=$(_gh_run repo view --json nameWithOwner -q .nameWithOwner) ||
        die 1 "list-threads: failed to detect current repo via gh"
      pr_number="${args[0]}"
      ;;
    2)
      owner_repo="${args[0]}"
      pr_number="${args[1]}"
      ;;
    *)
      die 1 "list-threads: too many arguments (expected 0, 1, or 2; got ${#args[@]})"
      ;;
    esac
    list_threads "${owner_repo}" "${pr_number}" || exit $?
    ;;
  *)
    die 1 "unknown subcommand: ${subcommand}"
    ;;
  esac
}

main "$@"
