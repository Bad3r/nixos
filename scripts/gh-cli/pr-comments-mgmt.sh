#!/usr/bin/env bash
# shellcheck disable=SC2016 # GraphQL queries use $vars as GraphQL variables, not shell vars
# pr-comments-mgmt.sh: resolve and/or minimize PR review threads via GitHub GraphQL.

set -Eeuo pipefail

PROG_NAME="${0##*/}"
QUIET=false
REASON="OUTDATED"

readonly VALID_REASONS=("OUTDATED" "RESOLVED" "OFF_TOPIC" "SPAM" "ABUSE" "DUPLICATE")

# Per-subcommand allowlist of long-flag short names (without the leading
# `--`). Every subcommand must register here; `_assert_flags_for` consults
# this map to reject flags that do not apply to the chosen subcommand.
declare -rA SUBCOMMAND_FLAGS=(
  ["resolve"]="quiet"
  ["hide-comment"]="quiet reason"
  ["hide-thread"]="quiet reason"
  ["list-threads"]="quiet pr"
  ["current-pr"]="quiet pr"
)

# Long-flag short names parsed off argv, preserved in order of appearance.
SET_FLAGS=()

# Raw `--pr <ref>` argument, resolved by `pr_resolve` into PR_OWNER_REPO
# and PR_NUMBER. Empty when --pr was not supplied.
PR_REF=""
PR_OWNER_REPO=""
PR_NUMBER=""

# `--body` / `--body-file` raw values; presence is tracked via SET_FLAGS
# (entries `body` and `body-file`) so empty bodies are distinguishable
# from "flag absent".
BODY_TEXT=""
BODY_FILE=""

# Plain-text on purpose: every other error is NDJSON, but `_json_string`
# itself depends on `jq`, so we cannot format this one as JSON.
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
  list-threads                             Print thread IDs (+ resolution and
                                           comment node IDs) as JSON for the
                                           PR named by `--pr`, or for the
                                           current branch's open PR when
                                           `--pr` is omitted.
  current-pr                               Print the PR named by `--pr` (or
                                           the current branch's open PR when
                                           `--pr` is omitted) as JSON
                                           (number, title, body, and labels
                                           as a name array). Exits non-zero
                                           if no PR is found.

Options:
  --pr <number|owner/repo#number>          Target a specific PR. With a bare
                                           number, the current repo is used.
                                           When omitted, the current branch's
                                           open PR is used.
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
  pr-comments-mgmt.sh hide-thread --reason OUTDATED PRRT_kwDOPeLwm85_EQHI
  pr-comments-mgmt.sh list-threads
  pr-comments-mgmt.sh --pr 123 list-threads
  pr-comments-mgmt.sh --pr owner/repo#123 list-threads
  pr-comments-mgmt.sh current-pr
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die 1 "required command not found: $1"
}

_gh_run() {
  # Run "gh $@". gh's stdout passes through to this function's stdout.
  # gh's stderr is captured: on failure it is re-emitted via `err` so
  # callers stay in JSON-only output mode; on success it is intentionally
  # dropped (typical content is interactive progress hints, deprecation
  # notices, etc., none of which belong in the structured stdout stream).
  # Returns gh's exit code.
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

_assert_flags_for() {
  # Args: <subcommand>
  # Dies if any flag in SET_FLAGS is not declared in SUBCOMMAND_FLAGS for
  # the given subcommand, or if the subcommand has no allowlist entry at
  # all (forces every new subcommand to register explicitly).
  local subcommand="$1"
  if [[ -z ${SUBCOMMAND_FLAGS[${subcommand}]+x} ]]; then
    die 1 "internal: no flag allowlist for subcommand '${subcommand}'"
  fi
  local allowed=" ${SUBCOMMAND_FLAGS[${subcommand}]} "
  local flag
  for flag in "${SET_FLAGS[@]}"; do
    [[ ${allowed} == *" ${flag} "* ]] ||
      die 1 "${subcommand}: --${flag//_/-} is not applicable"
  done
}

_set_flags_has() {
  # Args: <flag>
  # Returns 0 iff <flag> was supplied on argv.
  local target="$1" f
  for f in "${SET_FLAGS[@]}"; do
    [[ ${f} == "${target}" ]] && return 0
  done
  return 1
}

_read_body() {
  # Args: <subcommand-tag> [<positional-body>]
  # Echoes the body text on stdout from exactly one of: --body-file
  # (where `-` reads stdin), --body, or a single positional argument.
  # Dies with code 1 if zero or multiple sources are supplied.
  local tag="$1"
  shift
  local positional=$#
  local has_body=0 has_body_file=0
  _set_flags_has body && has_body=1
  _set_flags_has body-file && has_body_file=1
  local sources=$((has_body + has_body_file))
  ((positional > 0)) && sources=$((sources + 1))
  ((sources == 1)) ||
    die 1 "${tag}: provide exactly one of <body>, --body, or --body-file"

  if ((has_body_file)); then
    if [[ ${BODY_FILE} == "-" ]]; then
      cat
    else
      [[ -r ${BODY_FILE} ]] ||
        die 1 "${tag}: --body-file '${BODY_FILE}' is not readable"
      cat -- "${BODY_FILE}"
    fi
  elif ((has_body)); then
    printf '%s' "${BODY_TEXT}"
  else
    printf '%s' "$1"
  fi
}

_collect_ids() {
  # Args: <ids...>
  # Echoes one id per line on stdout. With positionals, echoes those
  # (skipping empty strings). Without positionals, reads from stdin
  # ignoring blank lines and `# ...` comment lines.
  if (($# > 0)); then
    local id
    for id in "$@"; do
      [[ -n ${id} ]] && printf '%s\n' "${id}"
    done
    return 0
  fi
  local line
  while IFS= read -r line; do
    [[ -z ${line} || ${line} =~ ^[[:space:]]*# ]] && continue
    printf '%s\n' "${line}"
  done
}

_bulk_summary() {
  # Args: <verb> <ok> <failed>
  # Emits a single NDJSON record on stderr summarizing the run; always
  # emitted, even under --quiet (the per-action log lines are the noisy
  # channel that --quiet suppresses).
  local verb="$1" ok="$2" failed="$3"
  printf '{"level":"info","prog":%s,"verb":%s,"ok":%d,"failed":%d}\n' \
    "$(_json_string "${PROG_NAME}")" \
    "$(_json_string "${verb}")" \
    "${ok}" "${failed}" >&2
}

pr_resolve() {
  # Populate PR_OWNER_REPO and PR_NUMBER from PR_REF when set, otherwise
  # fall back to the current branch via gh. With an explicit PR_REF the
  # caller has named a PR by id, so no state assertion is performed; the
  # gh-fallback path keeps the historical "must be OPEN" guard.
  if [[ -n ${PR_REF} ]]; then
    if [[ ${PR_REF} =~ ^([^/[:space:]]+/[^/#[:space:]]+)#([0-9]+)$ ]]; then
      PR_OWNER_REPO=${BASH_REMATCH[1]}
      PR_NUMBER=${BASH_REMATCH[2]}
    elif [[ ${PR_REF} =~ ^[0-9]+$ ]]; then
      PR_OWNER_REPO=$(_gh_run repo view --json nameWithOwner -q .nameWithOwner) ||
        die 1 "--pr ${PR_REF}: failed to detect current repo via gh"
      PR_NUMBER=${PR_REF}
    else
      die 1 "--pr: expected <number> or <owner/repo>#<number>; got '${PR_REF}'"
    fi
    return 0
  fi

  PR_OWNER_REPO=$(_gh_run repo view --json nameWithOwner -q .nameWithOwner) ||
    die 1 "failed to detect current repo via gh"
  local pr_view
  pr_view=$(_gh_run pr view --json number,state) ||
    die 1 "failed to detect current PR via gh"
  local state
  state=$(printf '%s' "${pr_view}" | jq -r '.state')
  [[ ${state} == "OPEN" ]] ||
    die 1 "PR for current branch is ${state}, expected OPEN (use --pr to override)"
  PR_NUMBER=$(printf '%s' "${pr_view}" | jq -r '.number')
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
  pr_resolve
  local owner=${PR_OWNER_REPO%/*}
  local repo=${PR_OWNER_REPO#*/}
  local pr_number=${PR_NUMBER}

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
  pr_resolve

  local data
  if ! data=$(_gh_run pr view "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
    --json number,title,body,labels,state); then
    err "current-pr: failed to view ${PR_OWNER_REPO}#${PR_NUMBER}"
    return 1
  fi

  printf '%s' "${data}" | jq 'del(.state) | .labels |= map(.name)'
}

main() {
  require_cmd gh

  local positional=()
  while (($# > 0)); do
    case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --quiet)
      QUIET=true
      SET_FLAGS+=(quiet)
      shift
      ;;
    --reason)
      [[ -n ${2:-} ]] || die 1 "--reason requires a value"
      valid_reason "$2" || die 1 "--reason must be one of: ${VALID_REASONS[*]}"
      REASON="$2"
      SET_FLAGS+=(reason)
      shift 2
      ;;
    --reason=*)
      local rv="${1#--reason=}"
      valid_reason "${rv}" || die 1 "--reason must be one of: ${VALID_REASONS[*]}"
      REASON="${rv}"
      SET_FLAGS+=(reason)
      shift
      ;;
    --pr)
      [[ -n ${2:-} ]] || die 1 "--pr requires a value"
      PR_REF="$2"
      SET_FLAGS+=(pr)
      shift 2
      ;;
    --pr=*)
      PR_REF="${1#--pr=}"
      [[ -n ${PR_REF} ]] || die 1 "--pr requires a value"
      SET_FLAGS+=(pr)
      shift
      ;;
    --body)
      [[ $# -ge 2 ]] || die 1 "--body requires a value"
      BODY_TEXT="$2"
      SET_FLAGS+=(body)
      shift 2
      ;;
    --body=*)
      BODY_TEXT="${1#--body=}"
      SET_FLAGS+=(body)
      shift
      ;;
    --body-file)
      [[ -n ${2:-} ]] || die 1 "--body-file requires a value"
      BODY_FILE="$2"
      SET_FLAGS+=(body-file)
      shift 2
      ;;
    --body-file=*)
      BODY_FILE="${1#--body-file=}"
      [[ -n ${BODY_FILE} ]] || die 1 "--body-file requires a value"
      SET_FLAGS+=(body-file)
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
    _assert_flags_for "${subcommand}"
    local id ok=0 failed=0
    while IFS= read -r id; do
      if resolve_thread "${id}"; then ok=$((ok + 1)); else failed=$((failed + 1)); fi
    done < <(_collect_ids "${args[@]}")
    _bulk_summary resolve "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  hide-comment)
    _assert_flags_for "${subcommand}"
    local id ok=0 failed=0
    while IFS= read -r id; do
      if minimize_comment "${id}" "${REASON}"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _bulk_summary hide-comment "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  hide-thread)
    _assert_flags_for "${subcommand}"
    local id ok=0 failed=0
    while IFS= read -r id; do
      if hide_thread "${id}" "${REASON}"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _bulk_summary hide-thread "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  current-pr)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} == 0)) || die 1 "current-pr: takes no arguments"
    current_pr || exit $?
    ;;
  list-threads)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} == 0)) || die 1 "list-threads: takes no positional arguments (use --pr)"
    list_threads || exit $?
    ;;
  *)
    die 1 "unknown subcommand: ${subcommand}"
    ;;
  esac
}

main "$@"
