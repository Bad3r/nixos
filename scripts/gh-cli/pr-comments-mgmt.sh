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
  ["resolve"]="quiet pr"
  ["hide-comment"]="quiet pr reason"
  ["hide-thread"]="quiet pr reason"
  ["list-threads"]="quiet pr format sort limit unresolved outdated author path minimized"
  ["list-reviews"]="quiet pr format sort limit"
  ["list-comments"]="quiet pr format sort limit author minimized"
  ["current-pr"]="quiet pr"
  ["get-thread"]="quiet pr"
  ["reply"]="quiet pr body body-file"
  ["unresolve"]="quiet pr"
  ["unhide-comment"]="quiet pr"
  ["dismiss-review"]="quiet pr body body-file"
  ["set-title"]="quiet pr"
  ["set-body"]="quiet pr body body-file"
  ["add-label"]="quiet pr"
  ["remove-label"]="quiet pr"
  ["set-labels"]="quiet pr"
  ["comment"]="quiet pr body body-file"
  ["review"]="quiet pr body body-file approve request-changes comment"
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

# Output format for list-* subcommands. One of "json" (default, pretty
# array), "ndjson" (one document per line), "ids" (one .id per line),
# "text" (one short line per item), "full" (header + body block per
# item), or "tsv" (per-kind tab-separated columns). text/full/tsv are
# dispatched per verb to pick relevant fields.
OUTPUT_FORMAT="json"

# list-threads filters. Presence is tracked via SET_FLAGS for the boolean
# filters (unresolved, outdated) so empty values do not collide with
# "flag absent". The author/path/minimized values are read off these
# globals when their flags are set.
FILTER_AUTHOR=""
FILTER_PATH=""
FILTER_MINIMIZED=""

# View options for list-* subcommands. SORT_ORDER is "newest" or
# "oldest" when set; LIMIT_VAL is a positive integer when set.
# Presence is tracked via SET_FLAGS so an empty value never silently
# means "no flag".
SORT_ORDER=""
LIMIT_VAL=""

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
pr-comments-mgmt.sh: GitHub PR review-thread and PR-write CLI.

Wraps `gh api graphql` and `gh pr {edit,comment,review,view}` so triage
workflows can stay on one CLI surface with one output convention. All
mutation results and per-action progress are NDJSON on stderr; structured
payloads land on stdout.

Read subcommands:
  list-threads                             Paginated review threads (with
                                           inner comment pagination merged).
                                           Default output: JSON array.
  list-reviews                             Paginated reviews (state, body,
                                           author, submittedAt, url, commit).
                                           Default output: JSON array.
  list-comments                            Paginated issue-level (top-level)
                                           PR conversation comments. Per
                                           comment: id, databaseId, author,
                                           body, createdAt, updatedAt, url,
                                           isMinimized, minimizedReason,
                                           viewerCan{Minimize,Update,Delete}.
                                           Default output: JSON array.
  get-thread <thread-id>                   Single review thread, same shape
                                           as one element of list-threads.
  current-pr                               PR view as JSON. Fields:
                                           id, number, title, body, state,
                                           url, headRefName, baseRefName,
                                           author, isDraft, mergeable,
                                           mergeStateStatus, and labels
                                           flattened to a name array.

Thread mutation subcommands (bulk; positional ids or stdin):
  resolve <thread-id>...                   Close one or more review threads.
  unresolve <thread-id>...                 Reopen one or more review threads.
  hide-comment <comment-node-id>...        Minimize comments via the active
                                           --reason classifier.
  unhide-comment <comment-node-id>...      Unminimize comments.
  hide-thread <thread-id>...               Minimize every visible comment in
                                           the thread then resolve it.
  reply <thread-id> [body|--body|--body-file FILE]
                                           Post a threaded reply via
                                           addPullRequestReviewThreadReply.
  dismiss-review <review-node-id>... --body|--body-file FILE
                                           Dismiss one or more PR reviews
                                           via dismissPullRequestReview.
                                           Only APPROVED and
                                           CHANGES_REQUESTED reviews are
                                           dismissable; COMMENTED and
                                           PENDING reviews are rejected
                                           by GitHub at runtime even
                                           though the input type accepts
                                           any review id. Message is
                                           required and shared across
                                           all ids. Irreversible (no
                                           undismiss mutation in the
                                           public API).

PR write subcommands:
  set-title <text>                         Edit PR title.
  set-body [body|--body|--body-file FILE]  Edit PR body.
  add-label <name>...                      Bulk add labels (positional or
                                           stdin).
  remove-label <name>...                   Bulk remove labels (positional or
                                           stdin).
  set-labels <name>...                     Set the PR's labels to exactly
                                           the supplied set (computes
                                           add/remove diff).
  comment [body|--body|--body-file FILE]   Post an issue-level (top-level)
                                           PR conversation comment.
                                           (Distinct from review's
                                           --comment event flag below.)
  review --approve|--request-changes|--comment [--body|--body-file FILE]
                                           Submit a PR review. --approve
                                           permits an empty body; the
                                           others require a non-empty body.
                                           Note: the --comment flag here
                                           selects the review event
                                           "COMMENT" and is unrelated to
                                           the standalone `comment`
                                           subcommand.

Options:
  --pr <number|owner/repo#number>          Target a specific PR. With a bare
                                           number, the current repo is used.
                                           When omitted, the current branch's
                                           open PR is used.
  --reason {OUTDATED|RESOLVED|OFF_TOPIC|SPAM|ABUSE|DUPLICATE}
                                           Classifier for hide-comment and
                                           hide-thread (default: OUTDATED).
  --format json|ndjson|ids|text|full|tsv   Output format for list-threads,
                                           list-reviews, and list-comments
                                           (default: json). `ids` emits
                                           one `.id` per line; `text`
                                           emits a one-line summary per
                                           item; `full` emits a header
                                           plus body block per item;
                                           `tsv` emits one tab-separated
                                           record per item with per-verb
                                           columns (no header — pipe to
                                           `column -t` for visual
                                           columns or `cut -f<n>` /
                                           `awk -F'\t'` downstream).
                                           tsv columns:
                                             reviews:  id, submittedAt,
                                             author, state, body_len,
                                             url
                                             comments: id, createdAt,
                                             author, isMinimized,
                                             minimizedReason, body_len,
                                             url
                                             threads:  id, isResolved,
                                             isOutdated, path, line,
                                             first_author, comments,
                                             unminimized
  --sort newest|oldest                     Sort list-* output by the natural
                                           per-item timestamp
                                           (submittedAt for reviews,
                                           createdAt for comments and the
                                           thread's first comment).
                                           `newest` places null timestamps
                                           (PENDING reviews) at the tail,
                                           so `--sort newest --limit N`
                                           never surfaces a pending
                                           review while any submitted
                                           review exists.
  --limit N                                Keep the first N items. Without
                                           --sort, items are kept in
                                           cursor-pagination order
                                           (typically oldest-first as
                                           returned by GitHub). Pair with
                                           `--sort newest --limit 5` for
                                           the five most recent items.
  --unresolved                             list-threads filter: keep
                                           threads with isResolved == false.
  --outdated                               list-threads filter: keep
                                           threads with isOutdated == true.
  --author <login>                         list-threads filter: keep threads
                                           whose first comment was authored
                                           by <login>. list-comments
                                           filter: keep comments authored
                                           by <login>.
  --path <glob>                            list-threads filter: keep threads
                                           whose path matches the glob.
                                           Wildcards: `*` (within a path
                                           segment), `?` (one non-`/`
                                           char), `**` (zero or more
                                           directory levels via `**/`,
                                           one or more trailing levels
                                           via `/**`). Backslash escapes
                                           (e.g., `\*` for a literal
                                           star) are not supported;
                                           review-thread paths
                                           realistically never contain
                                           glob meta-characters.
  --minimized true|false                   list-threads filter: keep threads
                                           where every comment is minimized
                                           (true) or where at least one
                                           comment is not (false).
                                           list-comments filter: keep
                                           comments where isMinimized
                                           matches the value.
  --body <text>, --body-file <path|->      Body source for reply, set-body,
                                           comment, and review. `-` means
                                           stdin.
  --approve, --request-changes, --comment  Review event flag (review only).
  --quiet                                  Suppress per-action progress
                                           lines (the bulk summary is still
                                           emitted).
  -h, --help                               Show this message.

Bulk verbs (resolve, unresolve, hide-comment, unhide-comment, hide-thread,
dismiss-review, add-label, remove-label) accept ids or names on stdin when
no positional arguments are given (one per line, blank and `# ...` lines
ignored), and emit a final summary record `{"verb":...,"ok":N,"failed":M}`
on stderr.

Exit codes:
  0   success
  1   user error (bad args, missing prerequisites)
  2   API error (one or more bulk-verb actions failed)

Examples:
  pr-comments-mgmt.sh resolve PRRT_kwDOPeLwm85_EPVC
  pr-comments-mgmt.sh hide-thread --reason OUTDATED PRRT_kwDOPeLwm85_EQHI
  pr-comments-mgmt.sh list-threads --format=ndjson --unresolved
  pr-comments-mgmt.sh --pr 123 list-threads --author Bad3r --path '*.sh'
  pr-comments-mgmt.sh --pr owner/repo#123 list-reviews
  pr-comments-mgmt.sh --pr 149 list-comments \
    --minimized=false --format=ids \
    | pr-comments-mgmt.sh hide-comment --pr 149 --reason RESOLVED
  pr-comments-mgmt.sh --pr 149 list-reviews --format=ndjson \
    | jq -r 'select(.state == "CHANGES_REQUESTED") | .id' \
    | pr-comments-mgmt.sh dismiss-review --pr 149 \
        --body 'addressed in commit abc1234; dismissing stale review'
  pr-comments-mgmt.sh --pr 149 list-reviews \
    --sort=newest --limit=1 --format=full
  pr-comments-mgmt.sh --pr 149 list-reviews \
    --sort=newest --limit=5 --format=text
  pr-comments-mgmt.sh --pr 149 list-comments \
    --sort=newest --limit=3 --format=full
  pr-comments-mgmt.sh --pr 149 list-threads --format=tsv \
    | awk -F'\t' -v OFS='\t' \
        'BEGIN{print "id","resolved","outdated","path","line","author","comments","unmin"} 1' \
    | column -t -s $'\t'
  pr-comments-mgmt.sh get-thread PRRT_kwDOPeLwm85_EPVC
  pr-comments-mgmt.sh reply PRRT_kwDOPeLwm85_EPVC --body 'ack'
  pr-comments-mgmt.sh --pr 149 set-labels 'type(enhancement)' 'area(scripts)'
  pr-comments-mgmt.sh --pr 149 comment --body-file response.md
  pr-comments-mgmt.sh --pr 149 review --comment --body 'LGTM'
  pr-comments-mgmt.sh list-threads --format=ndjson --unresolved \
    | jq -r '.id' | pr-comments-mgmt.sh resolve
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
  #
  # On the stdin path, the pre-filter line count is written to
  # ${BULK_READ_COUNT_FILE} when that env var is set, so callers can
  # distinguish "stdin was empty" (count=0) from "stdin had only blank
  # / comment lines" (count>0) when no ids end up emitted.
  if (($# > 0)); then
    local id
    for id in "$@"; do
      [[ -n ${id} ]] && printf '%s\n' "${id}"
    done
    return 0
  fi
  local line count=0
  while IFS= read -r line || [[ -n ${line} ]]; do
    count=$((count + 1))
    [[ -z ${line} || ${line} =~ ^[[:space:]]*# ]] && continue
    printf '%s\n' "${line}"
  done
  [[ -n ${BULK_READ_COUNT_FILE:-} ]] && printf '%d' "${count}" >"${BULK_READ_COUNT_FILE}"
  return 0
}

_glob_to_regex() {
  # gitignore-style glob -> jq-compatible anchored regex.
  #
  #   `?`   one char, but never `/`         -> [^/]
  #   `*`   any run within a path segment   -> [^/]*
  #   `**/` zero or more directory levels   -> (?:[^/]+/)*
  #   `/**` one or more trailing levels     -> (?:/[^/]+)+
  #   `**`  any chars including `/`         -> .*
  #
  # Globstar tokens are extracted via NUL-byte placeholders before the
  # `*` / `?` rewrite so the bare-`*` rule (which now stops at `/`) does
  # not eat their inner stars. Every other regex meta-char is escaped.
  # Backslash escapes are intentionally not supported: review-thread
  # paths realistically never contain literal `*`/`?` characters, and a
  # `\*`-style passthrough would complicate the placeholder ordering
  # without paying back any real-world coverage.
  local glob="$1"
  local re=${glob}
  re=${re//\\/\\\\}
  re=${re//./\\.}
  re=${re//+/\\+}
  re=${re//(/\\(}
  re=${re//)/\\)}
  re=${re//\[/\\[}
  re=${re//\]/\\]}
  re=${re//\{/\\\{}
  re=${re//\}/\\\}}
  re=${re//|/\\|}
  re=${re//^/\\^}
  re=${re//\$/\\\$}
  # Globstar placeholders. Order matters: `**/` and `/**` first, then bare `**`.
  local g1=$'\x01' g2=$'\x02' g3=$'\x03'
  re=${re//\*\*\//${g1}}
  re=${re//\/\*\*/${g2}}
  re=${re//\*\*/${g3}}
  re=${re//\*/[^/]*}
  re=${re//\?/[^/]}
  re=${re//${g1}/(?:[^/]+/)*}
  re=${re//${g2}/(?:/[^/]+)+}
  re=${re//${g3}/.*}
  printf '^%s$' "${re}"
}

_apply_comment_filters() {
  # Reads a JSON array of issue-level (top-level) comments on stdin
  # (the shape `list-comments` produces) and emits a filtered array.
  # No-op when no `--author` or `--minimized` flag was supplied.
  local jq_filter='.'
  local jq_args=()
  if _set_flags_has author; then
    jq_filter+=' | map(select((.author.login // "") == $author))'
    jq_args+=(--arg author "${FILTER_AUTHOR}")
  fi
  if _set_flags_has minimized; then
    if [[ ${FILTER_MINIMIZED} == "true" ]]; then
      jq_filter+=' | map(select(.isMinimized))'
    else
      jq_filter+=' | map(select(.isMinimized | not))'
    fi
  fi
  jq "${jq_args[@]}" "${jq_filter}"
}

_apply_thread_filters() {
  # Reads a JSON array of threads on stdin, emits a filtered array.
  # No-op when no `--unresolved`, `--outdated`, `--author`, `--path`, or
  # `--minimized` flag was supplied.
  local jq_filter='.'
  local jq_args=()
  if _set_flags_has unresolved; then
    jq_filter+=' | map(select(.isResolved | not))'
  fi
  if _set_flags_has outdated; then
    jq_filter+=' | map(select(.isOutdated))'
  fi
  if _set_flags_has author; then
    jq_filter+=' | map(select((.comments.nodes[0].author.login // "") == $author))'
    jq_args+=(--arg author "${FILTER_AUTHOR}")
  fi
  if _set_flags_has path; then
    jq_filter+=' | map(select(.path | test($path_re)))'
    jq_args+=(--arg path_re "$(_glob_to_regex "${FILTER_PATH}")")
  fi
  if _set_flags_has minimized; then
    if [[ ${FILTER_MINIMIZED} == "true" ]]; then
      jq_filter+=' | map(select((.comments.nodes | length) > 0 and all(.comments.nodes[]; .isMinimized)))'
    else
      jq_filter+=' | map(select(any(.comments.nodes[]; .isMinimized | not)))'
    fi
  fi
  jq "${jq_args[@]}" "${jq_filter}"
}

_apply_view() {
  # Reads a JSON array on stdin and applies --sort + --limit. The first
  # arg is the jq path expression for the per-item timestamp used by
  # --sort (e.g., `.submittedAt`, `.createdAt`,
  # `.comments.nodes[0].createdAt`). No-op when neither flag is set.
  local time_field="$1"
  local jq_filter='.'
  local jq_args=()
  if _set_flags_has sort; then
    jq_filter+=" | sort_by(${time_field})"
    [[ ${SORT_ORDER} == newest ]] && jq_filter+=' | reverse'
  fi
  if _set_flags_has limit; then
    jq_filter+=' | .[0:$lim]'
    jq_args+=(--argjson lim "${LIMIT_VAL}")
  fi
  jq "${jq_args[@]}" "${jq_filter}"
}

_format_array() {
  # Filter for list-* subcommands. Reads a JSON array on stdin; emits
  # one of six shapes per OUTPUT_FORMAT:
  #   json   pretty-printed JSON array (default)
  #   ndjson one JSON document per line
  #   ids    one `.id` per line, blank/null ids skipped
  #   text   one short summary line per item (per-kind fields)
  #   full   header + body block per item (per-kind layout)
  #   tsv    one tab-separated record per item (per-kind columns,
  #          no header — pipe to `column -t` for visual columns or
  #          `cut -f<n>` / `awk -F'\t'` for downstream parsing)
  # The first arg is the kind ("threads", "reviews", "comments") and
  # selects per-verb templates for text/full/tsv.
  local kind="$1"
  case "${OUTPUT_FORMAT}" in
  ndjson) jq -c '.[]' ;;
  ids) jq -r '.[].id // empty' ;;
  text) _format_text "${kind}" ;;
  full) _format_full "${kind}" ;;
  tsv) _format_tsv "${kind}" ;;
  *) jq '.' ;;
  esac
}

_format_text() {
  case "$1" in
  reviews)
    jq -r '.[] | "[\(.submittedAt)] \(.author.login) (\(.state)) body=\((.body // "") | length) chars"'
    ;;
  comments)
    jq -r '.[] | "[\(.createdAt)] \(.author.login)\(if .isMinimized then " [minimized:\(.minimizedReason // "?")]" else "" end) body=\((.body // "") | length) chars"'
    ;;
  threads)
    jq -r '.[] | "[\(.path // "?"):\(.line // "?")] \(.comments.nodes[0].author.login // "?") resolved=\(.isResolved) outdated=\(.isOutdated) comments=\(.comments.nodes | length)"'
    ;;
  *) die 1 "_format_text: unknown kind '$1'" ;;
  esac
}

_format_full() {
  # `threads` renders only the thread-opener's body. Use `get-thread <id>`
  # for the full reply chain; `full` is meant as a one-block-per-thread
  # summary, not a thread dump.
  case "$1" in
  reviews)
    jq -r '.[] | "=== [\(.submittedAt)] \(.author.login) (\(.state)) ===\n\(.body // "")\n"'
    ;;
  comments)
    jq -r '.[] | "=== [\(.createdAt)] \(.author.login)\(if .isMinimized then " [minimized:\(.minimizedReason // "?")]" else "" end) ===\n\(.body // "")\n"'
    ;;
  threads)
    jq -r '.[] | "=== [\(.path // "?"):\(.line // "?")] \(.comments.nodes[0].author.login // "?") resolved=\(.isResolved) outdated=\(.isOutdated) ===\n\(.comments.nodes[0].body // "")\n"'
    ;;
  *) die 1 "_format_full: unknown kind '$1'" ;;
  esac
}

_format_tsv() {
  # Per-verb tab-separated columns. No header row — this is meant to
  # feed straight into awk/cut/column. Body length is reported instead
  # of the body itself so a row stays one line.
  case "$1" in
  reviews)
    # id, submittedAt, author, state, body_len, url
    jq -r '.[] | [.id, .submittedAt, .author.login, .state, ((.body // "") | length), .url] | @tsv'
    ;;
  comments)
    # id, createdAt, author, isMinimized, minimizedReason, body_len, url
    jq -r '.[] | [.id, .createdAt, .author.login, .isMinimized, (.minimizedReason // ""), ((.body // "") | length), .url] | @tsv'
    ;;
  threads)
    # id, isResolved, isOutdated, path, line, first_author, comments,
    # unminimized — matches the recurring "thread audit" workflow.
    jq -r '.[] | [
      .id,
      .isResolved,
      .isOutdated,
      (.path // ""),
      (.line // ""),
      (.comments.nodes[0].author.login // ""),
      (.comments.nodes | length),
      (.comments.nodes | map(select(.isMinimized | not)) | length)
    ] | @tsv'
    ;;
  *) die 1 "_format_tsv: unknown kind '$1'" ;;
  esac
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

_bulk_count_file_init() {
  # Creates the temp file used by `_collect_ids` to record its
  # pre-filter line count, in the shell variable
  # ${BULK_READ_COUNT_FILE}. Caller must invoke `_bulk_count_file_done`
  # after the loop to reset the variable and remove the file. An EXIT
  # trap also fires `_bulk_count_file_done` so the file is cleaned up
  # on every exit path, including the `_assert_processed` -> die ->
  # exit branch which would otherwise bypass the explicit teardown.
  # No `export` needed: `_collect_ids` is invoked through process
  # substitution `< <(_collect_ids ...)`, which is a bash subshell and
  # inherits unexported variables. `export` only matters for child
  # processes started via `execve`, which this code path does not use.
  BULK_READ_COUNT_FILE=$(mktemp)
  trap '_bulk_count_file_done' EXIT
}

_bulk_count_file_done() {
  [[ -n ${BULK_READ_COUNT_FILE:-} ]] || return 0
  rm -f -- "${BULK_READ_COUNT_FILE}"
  unset BULK_READ_COUNT_FILE
}

_assert_processed() {
  # Args: <verb> <ok> <failed>
  # Dies when the bulk verb processed zero ids (positional + stdin both
  # empty, or stdin contained only blank / `#`-comment lines). A
  # zero-iteration run is indistinguishable from "everything succeeded"
  # via the exit code alone, so callers would lose the signal that
  # input never arrived (a closed pipe upstream, an empty filter
  # match, etc.). When the bulk loop set ${BULK_READ_COUNT_FILE}, the
  # message names the stdin line count so the caller can tell apart
  # "stdin closed" (read 0 lines) from "stdin had N lines, all
  # filtered" (read N lines).
  local verb="$1" ok="$2" failed="$3"
  (((ok + failed) > 0)) && return 0
  local detail="positional or stdin"
  if [[ -n ${BULK_READ_COUNT_FILE:-} && -s ${BULK_READ_COUNT_FILE} ]]; then
    local lines
    lines=$(<"${BULK_READ_COUNT_FILE}")
    if ((lines > 0)); then
      detail="read ${lines} stdin line(s), all blank/comment"
    else
      detail="positional empty, stdin empty"
    fi
  fi
  die 1 "${verb}: no ids supplied (${detail})"
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
  #
  # Each `field=value` is forwarded with `gh -F`, so numeric/boolean/null
  # values are typed correctly (Int/Boolean/null); a leading `raw:` prefix
  # forces `gh -f` instead, sending the value as a string verbatim. Use
  # `raw:` for arbitrary string payloads (e.g., review bodies) so values
  # that happen to look like `true`, `null`, or a number do not get
  # silently coerced.
  local query="$1"
  shift

  local args=()
  local kv
  for kv in "$@"; do
    case "${kv}" in
    raw:*) args+=(-f "${kv#raw:}") ;;
    *) args+=(-F "${kv}") ;;
    esac
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
  resolved=$(printf '%s' "${response}" |
    jq -r '.data.resolveReviewThread.thread.isResolved | tostring')

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
  is_min=$(printf '%s' "${response}" |
    jq -r '.data.minimizeComment.minimizedComment.isMinimized | tostring')

  if [[ ${is_min} != "true" ]]; then
    err "hide: unexpected response for ${node_id}: ${response}"
    return 2
  fi

  log "hidden (${classifier}): ${node_id}"
}

set_labels() {
  # Args: <desired-name>...
  # Sets the PR's labels to exactly the supplied set by computing the
  # add/remove diff against the current labels and issuing a single
  # `gh pr edit` call. No-op when the diff is empty. Refuses an empty
  # desired set: clearing every label is irrecoverable from this CLI's
  # perspective and is almost always a bug (empty positionals + closed
  # stdin), not an intent. Use `remove-label` explicitly to drop labels.
  (($# > 0)) ||
    die 1 "set-labels: refusing to clear all labels (empty desired set); use 'remove-label' to drop labels explicitly"
  pr_resolve

  local current
  current=$(_gh_run pr view "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
    --json labels -q '[.labels[].name]') ||
    return 2

  local desired
  desired=$(jq -n --args '$ARGS.positional | unique' "$@")

  local diff
  diff=$(jq -nc --argjson c "${current}" --argjson d "${desired}" \
    '{add: ($d - $c), remove: ($c - $d)}')

  local edit_args=() name
  while IFS= read -r name; do
    [[ -n ${name} ]] && edit_args+=(--add-label "${name}")
  done < <(printf '%s' "${diff}" | jq -r '.add[]')
  while IFS= read -r name; do
    [[ -n ${name} ]] && edit_args+=(--remove-label "${name}")
  done < <(printf '%s' "${diff}" | jq -r '.remove[]')

  if ((${#edit_args[@]} == 0)); then
    log "set-labels: no changes for ${PR_OWNER_REPO}#${PR_NUMBER}"
    return 0
  fi

  _gh_run pr edit "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
    "${edit_args[@]}" >/dev/null || return 2

  local added removed
  added=$(printf '%s' "${diff}" | jq -r '.add | length')
  removed=$(printf '%s' "${diff}" | jq -r '.remove | length')
  log "set-labels: ${PR_OWNER_REPO}#${PR_NUMBER} +${added} -${removed}"
}

unresolve_thread() {
  local thread_id="$1"
  [[ -n ${thread_id} ]] || die 1 "unresolve: empty thread id"

  local response
  if ! response=$(graphql_call '
mutation($id: ID!) {
  unresolveReviewThread(input: { threadId: $id }) {
    thread { id isResolved }
  }
}
' "id=${thread_id}"); then
    err "unresolve: graphql call failed for ${thread_id}"
    return 2
  fi

  local resolved
  resolved=$(printf '%s' "${response}" |
    jq -r '.data.unresolveReviewThread.thread.isResolved | tostring')

  case "${resolved}" in
  false) log "unresolved: ${thread_id}" ;;
  null)
    err "unresolve: unexpected response for ${thread_id}: ${response}"
    return 2
    ;;
  *)
    err "unresolve: ${thread_id} reported isResolved=${resolved}"
    return 2
    ;;
  esac
}

unminimize_comment() {
  local node_id="$1"
  [[ -n ${node_id} ]] || die 1 "unhide-comment: empty comment node id"

  local response
  if ! response=$(graphql_call '
mutation($id: ID!) {
  unminimizeComment(input: { subjectId: $id }) {
    unminimizedComment { isMinimized }
  }
}
' "id=${node_id}"); then
    err "unhide-comment: graphql call failed for ${node_id}"
    return 2
  fi

  local is_min
  is_min=$(printf '%s' "${response}" |
    jq -r '.data.unminimizeComment.unminimizedComment.isMinimized | tostring')
  if [[ ${is_min} != "false" ]]; then
    err "unhide-comment: unexpected response for ${node_id}: ${response}"
    return 2
  fi

  log "unhidden: ${node_id}"
}

dismiss_review() {
  # Args: <review-node-id> <message>
  # `dismissPullRequestReview` only accepts reviews in APPROVED or
  # CHANGES_REQUESTED state; COMMENTED and PENDING reviews are rejected
  # by GitHub at runtime ("Can not dismiss a commented pull request
  # review") even though the input type does not distinguish. The
  # mutation is irreversible via the public API (no undismiss).
  local review_id="$1"
  local message="$2"
  [[ -n ${review_id} ]] || die 1 "dismiss-review: empty review id"
  [[ -n ${message} ]] || die 1 "dismiss-review: message cannot be empty"

  local response
  if ! response=$(graphql_call '
mutation($id: ID!, $message: String!) {
  dismissPullRequestReview(input: { pullRequestReviewId: $id, message: $message }) {
    pullRequestReview { id state }
  }
}
' "id=${review_id}" "raw:message=${message}"); then
    err "dismiss-review: graphql call failed for ${review_id}"
    return 2
  fi

  local state
  state=$(printf '%s' "${response}" |
    jq -r '.data.dismissPullRequestReview.pullRequestReview.state // ""')
  if [[ ${state} != "DISMISSED" ]]; then
    err "dismiss-review: unexpected response for ${review_id}: ${response}"
    return 2
  fi

  log "dismissed: ${review_id}"
}

reply_thread() {
  local thread_id="$1"
  local body="$2"
  [[ -n ${thread_id} ]] || die 1 "reply: empty thread id"

  local response
  if ! response=$(graphql_call '
mutation($id: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $id,
    body: $body
  }) {
    comment { id databaseId url body author { login } }
  }
}
' "id=${thread_id}" "raw:body=${body}"); then
    err "reply: graphql call failed for ${thread_id}"
    return 2
  fi

  local cid
  cid=$(printf '%s' "${response}" | jq -r '.data.addPullRequestReviewThreadReply.comment.id // ""')
  [[ -n ${cid} ]] ||
    die 2 "reply: unexpected response for ${thread_id}: ${response}"

  log "replied: ${thread_id} -> ${cid}"
  printf '%s' "${response}" | jq '.data.addPullRequestReviewThreadReply.comment'
}

hide_thread() {
  local thread_id="$1"
  local classifier="$2"
  [[ -n ${thread_id} ]] || die 1 "hide-thread: empty thread id"

  # Cursor sentinel convention shared by every paginator below: bash
  # variable `"null"` is forwarded by `gh -F cursor=null` as the JSON
  # `null` literal (gh parses `-F` values as JSON-ish), which `$cursor:
  # String` accepts as "no cursor / first page". Subsequent iterations
  # overwrite it with `endCursor`. Any other sentinel string would be
  # rejected by GitHub as `Argument 'cursor' has an invalid value`.
  local cursor="null"
  # First-page-only __typename validation: a node id ↔ type mapping is
  # stable across pages on GitHub's side (the same id cannot be a
  # PullRequestReviewThread on page 1 and something else on page 2),
  # so checking once is sufficient.
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
        nodes {
          id
          databaseId
          author { login }
          body
          diffHunk
          originalLine
          originalStartLine
          subjectType
          isMinimized
          minimizedReason
        }
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

    thread=$(printf '%s\n%s' "${thread}" "${page}" | jq -s '
      .[0] as $t | .[1] as $p
      | $t | .comments.nodes += $p.data.node.comments.nodes
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
          isCollapsed
          path
          line
          subjectType
          resolvedBy { login }
          viewerCanResolve
          viewerCanUnresolve
          viewerCanReply
          comments(first: 100) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              databaseId
              author { login }
              body
              diffHunk
              originalLine
              originalStartLine
              subjectType
              isMinimized
              minimizedReason
            }
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
      page=$(printf '%s\n%s' "${page}" "${thread_out}" |
        jq -s --argjson i "${idx}" '.[0] as $p | .[1] as $t | $p | .[$i] = $t')
    done

    all_threads=$(printf '%s\n%s' "${all_threads}" "${page}" | jq -s 'add')

    local page_info has_next
    page_info=$(printf '%s' "${response}" |
      jq -c '.data.repository.pullRequest.reviewThreads.pageInfo')
    has_next=$(printf '%s' "${page_info}" | jq -r '.hasNextPage')
    [[ ${has_next} == "true" ]] || break
    cursor=$(printf '%s' "${page_info}" | jq -r '.endCursor')
  done

  printf '%s' "${all_threads}" | _apply_thread_filters |
    _apply_view '.comments.nodes[0].createdAt' | _format_array threads
}

list_reviews() {
  pr_resolve
  local owner=${PR_OWNER_REPO%/*}
  local repo=${PR_OWNER_REPO#*/}
  local pr_number=${PR_NUMBER}

  local cursor="null"
  local all_reviews='[]'

  while :; do
    local response
    if ! response=$(graphql_call '
query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviews(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          databaseId
          state
          body
          author { login }
          submittedAt
          url
          commit { oid }
        }
      }
    }
  }
}
' "owner=${owner}" "repo=${repo}" "number=${pr_number}" "cursor=${cursor}"); then
      err "list-reviews: graphql call failed"
      return 2
    fi

    if ! printf '%s' "${response}" | jq -e '.data.repository.pullRequest' >/dev/null; then
      err "list-reviews: ${owner}/${repo} pull request #${pr_number} not found"
      return 2
    fi

    local page
    page=$(printf '%s' "${response}" | jq '.data.repository.pullRequest.reviews.nodes')

    all_reviews=$(printf '%s\n%s' "${all_reviews}" "${page}" | jq -s 'add')

    local page_info has_next
    page_info=$(printf '%s' "${response}" |
      jq -c '.data.repository.pullRequest.reviews.pageInfo')
    has_next=$(printf '%s' "${page_info}" | jq -r '.hasNextPage')
    [[ ${has_next} == "true" ]] || break
    cursor=$(printf '%s' "${page_info}" | jq -r '.endCursor')
  done

  printf '%s' "${all_reviews}" | _apply_view '.submittedAt' | _format_array reviews
}

list_comments() {
  # Issue-level (top-level) PR conversation comments. Distinct from
  # `list-threads` (inline review comments) and `list-reviews` (review
  # submissions). The GraphQL `pullRequest.comments` connection backs
  # the `gh api repos/.../issues/<n>/comments` REST endpoint.
  pr_resolve
  local owner=${PR_OWNER_REPO%/*}
  local repo=${PR_OWNER_REPO#*/}
  local pr_number=${PR_NUMBER}

  local cursor="null"
  local all_comments='[]'

  while :; do
    local response
    if ! response=$(graphql_call '
query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      comments(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          databaseId
          author { login }
          body
          createdAt
          updatedAt
          url
          isMinimized
          minimizedReason
          viewerCanMinimize
          viewerCanUpdate
          viewerCanDelete
        }
      }
    }
  }
}
' "owner=${owner}" "repo=${repo}" "number=${pr_number}" "cursor=${cursor}"); then
      err "list-comments: graphql call failed"
      return 2
    fi

    if ! printf '%s' "${response}" | jq -e '.data.repository.pullRequest' >/dev/null; then
      err "list-comments: ${owner}/${repo} pull request #${pr_number} not found"
      return 2
    fi

    local page
    page=$(printf '%s' "${response}" | jq '.data.repository.pullRequest.comments.nodes')

    all_comments=$(printf '%s\n%s' "${all_comments}" "${page}" | jq -s 'add')

    local page_info has_next
    page_info=$(printf '%s' "${response}" |
      jq -c '.data.repository.pullRequest.comments.pageInfo')
    has_next=$(printf '%s' "${page_info}" | jq -r '.hasNextPage')
    [[ ${has_next} == "true" ]] || break
    cursor=$(printf '%s' "${page_info}" | jq -r '.endCursor')
  done

  printf '%s' "${all_comments}" | _apply_comment_filters |
    _apply_view '.createdAt' | _format_array comments
}

get_thread() {
  local thread_id="$1"
  [[ -n ${thread_id} ]] || die 1 "get-thread: empty thread id"

  local response
  if ! response=$(graphql_call '
query($id: ID!) {
  node(id: $id) {
    __typename
    ... on PullRequestReviewThread {
      id
      isResolved
      isOutdated
      isCollapsed
      path
      line
      subjectType
      resolvedBy { login }
      viewerCanResolve
      viewerCanUnresolve
      viewerCanReply
      comments(first: 100) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          databaseId
          author { login }
          body
          diffHunk
          originalLine
          originalStartLine
          subjectType
          isMinimized
          minimizedReason
        }
      }
    }
  }
}
' "id=${thread_id}"); then
    err "get-thread: graphql call failed for ${thread_id}"
    return 2
  fi

  local typename
  typename=$(printf '%s' "${response}" | jq -r '.data.node.__typename // ""')
  if [[ ${typename} != "PullRequestReviewThread" ]]; then
    err "get-thread: ${thread_id} is ${typename:-not found}, expected PullRequestReviewThread"
    return 2
  fi

  printf '%s' "${response}" | jq -c '.data.node | del(.__typename)' |
    _paginate_thread_comments | jq '.'
}

current_pr() {
  pr_resolve

  local data
  if ! data=$(_gh_run pr view "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" --json \
    id,number,title,body,state,url,headRefName,baseRefName,author,isDraft,mergeable,mergeStateStatus,labels); then
    err "current-pr: failed to view ${PR_OWNER_REPO}#${PR_NUMBER}"
    return 2
  fi

  printf '%s' "${data}" | jq '.labels |= map(.name)'
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
    --format)
      [[ -n ${2:-} ]] || die 1 "--format requires a value"
      case "$2" in
      json | ndjson | ids | text | full | tsv) OUTPUT_FORMAT="$2" ;;
      *) die 1 "--format must be one of: json, ndjson, ids, text, full, tsv" ;;
      esac
      SET_FLAGS+=(format)
      shift 2
      ;;
    --format=*)
      local fv="${1#--format=}"
      case "${fv}" in
      json | ndjson | ids | text | full | tsv) OUTPUT_FORMAT="${fv}" ;;
      *) die 1 "--format must be one of: json, ndjson, ids, text, full, tsv" ;;
      esac
      SET_FLAGS+=(format)
      shift
      ;;
    --sort)
      [[ -n ${2:-} ]] || die 1 "--sort requires a value"
      case "$2" in
      newest | oldest) SORT_ORDER="$2" ;;
      *) die 1 "--sort must be one of: newest, oldest" ;;
      esac
      SET_FLAGS+=(sort)
      shift 2
      ;;
    --sort=*)
      local sv="${1#--sort=}"
      case "${sv}" in
      newest | oldest) SORT_ORDER="${sv}" ;;
      *) die 1 "--sort must be one of: newest, oldest" ;;
      esac
      SET_FLAGS+=(sort)
      shift
      ;;
    --limit)
      [[ -n ${2:-} ]] || die 1 "--limit requires a value"
      [[ ${2} =~ ^[1-9][0-9]*$ ]] || die 1 "--limit must be a positive integer"
      LIMIT_VAL="$2"
      SET_FLAGS+=(limit)
      shift 2
      ;;
    --limit=*)
      local lv="${1#--limit=}"
      [[ ${lv} =~ ^[1-9][0-9]*$ ]] || die 1 "--limit must be a positive integer"
      LIMIT_VAL="${lv}"
      SET_FLAGS+=(limit)
      shift
      ;;
    --unresolved)
      SET_FLAGS+=(unresolved)
      shift
      ;;
    --outdated)
      SET_FLAGS+=(outdated)
      shift
      ;;
    --author)
      [[ -n ${2:-} ]] || die 1 "--author requires a value"
      FILTER_AUTHOR="$2"
      SET_FLAGS+=(author)
      shift 2
      ;;
    --author=*)
      FILTER_AUTHOR="${1#--author=}"
      [[ -n ${FILTER_AUTHOR} ]] || die 1 "--author requires a value"
      SET_FLAGS+=(author)
      shift
      ;;
    --path)
      [[ -n ${2:-} ]] || die 1 "--path requires a value"
      FILTER_PATH="$2"
      SET_FLAGS+=(path)
      shift 2
      ;;
    --path=*)
      FILTER_PATH="${1#--path=}"
      [[ -n ${FILTER_PATH} ]] || die 1 "--path requires a value"
      SET_FLAGS+=(path)
      shift
      ;;
    --minimized)
      [[ -n ${2:-} ]] || die 1 "--minimized requires a value (true|false)"
      case "$2" in
      true | false) FILTER_MINIMIZED="$2" ;;
      *) die 1 "--minimized must be one of: true, false" ;;
      esac
      SET_FLAGS+=(minimized)
      shift 2
      ;;
    --minimized=*)
      local mv="${1#--minimized=}"
      case "${mv}" in
      true | false) FILTER_MINIMIZED="${mv}" ;;
      *) die 1 "--minimized must be one of: true, false" ;;
      esac
      SET_FLAGS+=(minimized)
      shift
      ;;
    --approve)
      SET_FLAGS+=(approve)
      shift
      ;;
    --request-changes)
      SET_FLAGS+=(request-changes)
      shift
      ;;
    --comment)
      SET_FLAGS+=(comment)
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
    _bulk_count_file_init
    while IFS= read -r id; do
      if resolve_thread "${id}"; then ok=$((ok + 1)); else failed=$((failed + 1)); fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed resolve "${ok}" "${failed}"
    _bulk_count_file_done
    _bulk_summary resolve "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  hide-comment)
    _assert_flags_for "${subcommand}"
    local id ok=0 failed=0
    _bulk_count_file_init
    while IFS= read -r id; do
      if minimize_comment "${id}" "${REASON}"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed hide-comment "${ok}" "${failed}"
    _bulk_count_file_done
    _bulk_summary hide-comment "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  hide-thread)
    _assert_flags_for "${subcommand}"
    local id ok=0 failed=0
    _bulk_count_file_init
    while IFS= read -r id; do
      if hide_thread "${id}" "${REASON}"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed hide-thread "${ok}" "${failed}"
    _bulk_count_file_done
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
  list-reviews)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} == 0)) || die 1 "list-reviews: takes no positional arguments (use --pr)"
    list_reviews || exit $?
    ;;
  list-comments)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} == 0)) || die 1 "list-comments: takes no positional arguments (use --pr)"
    list_comments || exit $?
    ;;
  get-thread)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} == 1)) ||
      die 1 "get-thread: expected exactly one thread id (got ${#args[@]})"
    get_thread "${args[0]}" || exit $?
    ;;
  reply)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} >= 1)) || die 1 "reply: missing thread id"
    local rid="${args[0]}"
    local rbody
    rbody=$(_read_body reply "${args[@]:1}") || exit $?
    reply_thread "${rid}" "${rbody}" || exit $?
    ;;
  unresolve)
    _assert_flags_for "${subcommand}"
    local id ok=0 failed=0
    _bulk_count_file_init
    while IFS= read -r id; do
      if unresolve_thread "${id}"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed unresolve "${ok}" "${failed}"
    _bulk_count_file_done
    _bulk_summary unresolve "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  unhide-comment)
    _assert_flags_for "${subcommand}"
    local id ok=0 failed=0
    _bulk_count_file_init
    while IFS= read -r id; do
      if unminimize_comment "${id}"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed unhide-comment "${ok}" "${failed}"
    _bulk_count_file_done
    _bulk_summary unhide-comment "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  dismiss-review)
    _assert_flags_for "${subcommand}"
    if ! _set_flags_has body && ! _set_flags_has body-file; then
      die 1 "dismiss-review: --body or --body-file is required (positional args are review ids)"
    fi
    local dr_message
    dr_message=$(_read_body dismiss-review) || exit $?
    [[ -n ${dr_message} ]] ||
      die 1 "dismiss-review: message cannot be empty"
    local id ok=0 failed=0
    _bulk_count_file_init
    while IFS= read -r id; do
      if dismiss_review "${id}" "${dr_message}"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed dismiss-review "${ok}" "${failed}"
    _bulk_count_file_done
    _bulk_summary dismiss-review "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  set-title)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} == 1)) ||
      die 1 "set-title: expected exactly one title (got ${#args[@]})"
    [[ -n ${args[0]} ]] ||
      die 1 "set-title: title cannot be empty"
    pr_resolve
    _gh_run pr edit "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
      --title "${args[0]}" >/dev/null || exit $?
    log "set-title: ${PR_OWNER_REPO}#${PR_NUMBER}"
    ;;
  set-body)
    _assert_flags_for "${subcommand}"
    pr_resolve
    local sb_body
    sb_body=$(_read_body set-body "${args[@]}") || exit $?
    _gh_run pr edit "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
      --body "${sb_body}" >/dev/null || exit $?
    log "set-body: ${PR_OWNER_REPO}#${PR_NUMBER}"
    ;;
  add-label)
    _assert_flags_for "${subcommand}"
    pr_resolve
    local name ok=0 failed=0
    _bulk_count_file_init
    while IFS= read -r name; do
      if _gh_run pr edit "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
        --add-label "${name}" >/dev/null; then
        log "added: ${name}"
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed add-label "${ok}" "${failed}"
    _bulk_count_file_done
    _bulk_summary add-label "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  remove-label)
    _assert_flags_for "${subcommand}"
    pr_resolve
    local name ok=0 failed=0
    _bulk_count_file_init
    while IFS= read -r name; do
      if _gh_run pr edit "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
        --remove-label "${name}" >/dev/null; then
        log "removed: ${name}"
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_collect_ids "${args[@]}")
    _assert_processed remove-label "${ok}" "${failed}"
    _bulk_count_file_done
    _bulk_summary remove-label "${ok}" "${failed}"
    exit $((failed > 0 ? 2 : 0))
    ;;
  set-labels)
    _assert_flags_for "${subcommand}"
    local sl_names=() name
    while IFS= read -r name; do
      sl_names+=("${name}")
    done < <(_collect_ids "${args[@]}")
    set_labels "${sl_names[@]}" || exit $?
    ;;
  comment)
    _assert_flags_for "${subcommand}"
    pr_resolve
    local cm_body
    cm_body=$(_read_body comment "${args[@]}") || exit $?
    _gh_run pr comment "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
      --body "${cm_body}" || exit $?
    ;;
  review)
    _assert_flags_for "${subcommand}"
    ((${#args[@]} == 0)) ||
      die 1 "review: takes no positional arguments"
    pr_resolve
    local rv_event="" rv_count=0
    if _set_flags_has approve; then
      rv_event="--approve"
      rv_count=$((rv_count + 1))
    fi
    if _set_flags_has request-changes; then
      rv_event="--request-changes"
      rv_count=$((rv_count + 1))
    fi
    if _set_flags_has comment; then
      rv_event="--comment"
      rv_count=$((rv_count + 1))
    fi
    ((rv_count == 1)) ||
      die 1 "review: provide exactly one of --approve, --request-changes, --comment"
    local rv_body=""
    if _set_flags_has body || _set_flags_has body-file; then
      rv_body=$(_read_body review) || exit $?
    fi
    if [[ ${rv_event} != "--approve" && -z ${rv_body} ]]; then
      die 1 "review: ${rv_event} requires a non-empty body"
    fi
    if [[ -z ${rv_body} ]]; then
      _gh_run pr review "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
        "${rv_event}" || exit $?
    else
      _gh_run pr review "${PR_NUMBER}" --repo "${PR_OWNER_REPO}" \
        "${rv_event}" --body "${rv_body}" || exit $?
    fi
    log "review (${rv_event#--}): ${PR_OWNER_REPO}#${PR_NUMBER}"
    ;;
  *)
    die 1 "unknown subcommand: ${subcommand}"
    ;;
  esac
}

main "$@"
