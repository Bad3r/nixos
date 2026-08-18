#!/usr/bin/env bash
# shellcheck shell=bash
# Covers the help surface plus the one payload path a stub can serve end to
# end: `current-pr` reaches GitHub through a single `gh pr view`, so a canned
# fixture behind a stub `gh` renders every --format for real. Every other case
# stops at the first argument the parser rejects or at the missing `gh`
# binary. No case opens a socket.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/gh-cli/pr-comments-mgmt.sh"
BASH_BIN="$(command -v bash)"

if [[ ! -x ${SUT} ]]; then
  printf 'run.sh: SUT not executable at %s\n' "${SUT}" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

# PATH holding jq and nothing else, so `require_cmd gh` fails on demand. Every
# parser assertion below runs through it: a documented value that reaches the
# missing-gh error is a value the parser accepted.
NOGH_BIN="${tmpdir}/nogh-bin"
mkdir -p "${NOGH_BIN}"
ln -s "$(command -v jq)" "${NOGH_BIN}/jq"

# The same PATH plus a `gh` that satisfies `require_cmd` without being callable,
# for the paths that run past that check. `gh` is absent from the Nix check's
# input set, so without this stub those paths would stop at the missing binary
# and assert nothing.
WITHGH_BIN="${tmpdir}/withgh-bin"
mkdir -p "${WITHGH_BIN}"
ln -s "$(command -v jq)" "${WITHGH_BIN}/jq"
printf '#!/bin/sh\necho "run.sh: unexpected gh invocation: $*" >&2\nexit 97\n' >"${WITHGH_BIN}/gh"
chmod +x "${WITHGH_BIN}/gh"

# The same PATH again, with a `gh` that answers `pr view` from a canned payload
# in gh's own shape (labels as objects, author as a login object). `current-pr`
# with an explicit --pr makes exactly that one call, so this renders the real
# payload path without a socket. Every other gh invocation stays an error, so a
# case that starts calling the API announces itself.
PR_VIEW_FIXTURE="${tmpdir}/pr-view.json"
cat >"${PR_VIEW_FIXTURE}" <<'JSON'
{
  "id": "PR_kwDOtest0001",
  "number": 149,
  "title": "test(pr): canned payload",
  "body": "first body line\nsecond body line",
  "state": "OPEN",
  "url": "https://github.com/owner/repo/pull/149",
  "headRefName": "topic",
  "headRefOid": "1111111111111111111111111111111111111111",
  "baseRefName": "main",
  "baseRefOid": "2222222222222222222222222222222222222222",
  "author": { "login": "octocat" },
  "isDraft": false,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "CLEAN",
  "labels": [{ "name": "type(fix)" }, { "name": "area(scripts)" }]
}
JSON
PRVIEW_BIN="${tmpdir}/prview-bin"
mkdir -p "${PRVIEW_BIN}"
ln -s "$(command -v jq)" "${PRVIEW_BIN}/jq"
# The stub itself runs under this PATH, so the one external it uses is linked
# in alongside jq rather than assumed.
ln -s "$(command -v cat)" "${PRVIEW_BIN}/cat"
# shellcheck disable=SC2016 # $1/$2/$* belong to the stub being written, not here
printf '#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = view ]; then exec cat %s; fi\necho "run.sh: unexpected gh invocation: $*" >&2\nexit 97\n' \
  "${PR_VIEW_FIXTURE}" >"${PRVIEW_BIN}/gh"
chmod +x "${PRVIEW_BIN}/gh"

# Three more canned-payload stubs, same shape as PRVIEW_BIN but answering
# `gh api graphql` (what get-thread and get-comment call through
# graphql_call) instead of `pr view`. Each renders one specific node shape end
# to end: a review thread with replies (get-thread's silent reply-chain drop
# under --format=full/body), an inline review comment, and a top-level issue
# comment (get-comment's typename-keyed comments/review-comments split).
THREAD_FIXTURE="${tmpdir}/thread.json"
cat >"${THREAD_FIXTURE}" <<'JSON'
{
  "data": {
    "node": {
      "__typename": "PullRequestReviewThread",
      "id": "PRRT_test0001",
      "isResolved": false,
      "isOutdated": false,
      "isCollapsed": false,
      "path": "scripts/gh-cli/pr-comments-mgmt.sh",
      "line": 42,
      "startLine": null,
      "diffSide": "RIGHT",
      "startDiffSide": null,
      "subjectType": "LINE",
      "resolvedBy": null,
      "viewerCanResolve": true,
      "viewerCanUnresolve": false,
      "viewerCanReply": true,
      "comments": {
        "pageInfo": { "hasNextPage": false, "endCursor": "cursor1" },
        "nodes": [
          {
            "id": "PRRC_test0001",
            "databaseId": 1,
            "author": { "login": "claude" },
            "body": "opener-body",
            "createdAt": "2026-08-18T00:00:00Z",
            "diffHunk": "@@ -1 +1 @@",
            "originalLine": 42,
            "originalStartLine": null,
            "subjectType": "LINE",
            "isMinimized": false,
            "minimizedReason": null
          },
          {
            "id": "PRRC_test0002",
            "databaseId": 2,
            "author": { "login": "Bad3r" },
            "body": "first-reply-body",
            "createdAt": "2026-08-18T00:01:00Z",
            "diffHunk": "@@ -1 +1 @@",
            "originalLine": 42,
            "originalStartLine": null,
            "subjectType": "LINE",
            "isMinimized": false,
            "minimizedReason": null
          },
          {
            "id": "PRRC_test0003",
            "databaseId": 3,
            "author": { "login": "claude" },
            "body": "second-reply-body",
            "createdAt": "2026-08-18T00:02:00Z",
            "diffHunk": "@@ -1 +1 @@",
            "originalLine": 42,
            "originalStartLine": null,
            "subjectType": "LINE",
            "isMinimized": false,
            "minimizedReason": null
          }
        ]
      }
    }
  }
}
JSON
THREAD_BIN="${tmpdir}/thread-bin"
mkdir -p "${THREAD_BIN}"
ln -s "$(command -v jq)" "${THREAD_BIN}/jq"
ln -s "$(command -v cat)" "${THREAD_BIN}/cat"
# shellcheck disable=SC2016 # $1/$2/$* belong to the stub being written, not here
printf '#!/bin/sh\nif [ "$1" = api ] && [ "$2" = graphql ]; then exec cat %s; fi\necho "run.sh: unexpected gh invocation: $*" >&2\nexit 97\n' \
  "${THREAD_FIXTURE}" >"${THREAD_BIN}/gh"
chmod +x "${THREAD_BIN}/gh"

LAST_RC=0
LAST_OUT=""
LAST_ERR=""

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_without_gh() {
  LAST_RC=0
  LAST_OUT="$(PATH="${NOGH_BIN}" "${BASH_BIN}" "${SUT}" "$@" 2>"${tmpdir}/stderr")" || LAST_RC=$?
  LAST_ERR="$(<"${tmpdir}/stderr")"
}

# shellcheck disable=SC2120 # general helper; the one case that needs it so far passes no args
run_with_gh() {
  # Same capture, past `require_cmd gh`, with the two streams kept apart. The
  # stub PATH needs no `head` here, so it is substituted rather than prepended.
  LAST_RC=0
  LAST_OUT="$(PATH="${WITHGH_BIN}" "${BASH_BIN}" "${SUT}" "$@" 2>"${tmpdir}/stderr")" || LAST_RC=$?
  LAST_ERR="$(<"${tmpdir}/stderr")"
}

run_with_pr_view() {
  # Same capture against the canned-payload stub. --pr is supplied by the
  # caller so pr_resolve never calls gh; the run's only invocation is the
  # `pr view` the stub answers.
  LAST_RC=0
  LAST_OUT="$(PATH="${PRVIEW_BIN}" "${BASH_BIN}" "${SUT}" "$@" 2>"${tmpdir}/stderr")" || LAST_RC=$?
  LAST_ERR="$(<"${tmpdir}/stderr")"
}

run_with_thread() {
  # Same capture against the canned review-thread stub. get-thread does not
  # call pr_resolve for a direct node id, so a bare thread id needs no --pr
  # and makes exactly the one graphql call the stub answers.
  LAST_RC=0
  LAST_OUT="$(PATH="${THREAD_BIN}" "${BASH_BIN}" "${SUT}" "$@" 2>"${tmpdir}/stderr")" || LAST_RC=$?
  LAST_ERR="$(<"${tmpdir}/stderr")"
}

assert_last_ok() {
  # Args: <what>
  # Fails unless the most recent run_with_* call exited 0 and wrote no
  # diagnostics. Split out of assert_pr_view_ok so the thread/comment stubs
  # can reuse the same "exits 0 quietly" check without re-running the call.
  local what="$1"
  [[ ${LAST_RC} -eq 0 ]] || fail "${what} exited ${LAST_RC}: ${LAST_ERR}"
  [[ -z ${LAST_ERR} ]] || fail "${what} wrote diagnostics: ${LAST_ERR}"
}

assert_pr_view_ok() {
  # Args: <what> <arg>...
  # Runs the SUT against the stub and fails unless it exits 0 quietly.
  local what="$1"
  shift
  run_with_pr_view "$@"
  assert_last_ok "${what}"
}

# Inner shell for run_piped_sigpipe_ignored. Single-quoted on purpose: $@ and
# PIPESTATUS belong to that shell, not this one.
# shellcheck disable=SC2016
readonly SIGPIPE_WRAPPER='
  trap "" PIPE
  merge="$1"
  shift
  if [ "${merge}" = merge ]; then
    "$@" 2>&1 | head -1
    rc=${PIPESTATUS[0]}
  else
    "$@" | head -1 >/dev/null
    rc=${PIPESTATUS[0]}
  fi
  exit "${rc}"'

run_piped_sigpipe_ignored() {
  # Args: [--merge-stderr] <arg>...
  # Runs `<sut> "$@" | head -1` with SIGPIPE ignored: `trap "" PIPE` sets
  # SIG_IGN, which survives exec, so the closed reader reaches the SUT as an
  # EPIPE write error rather than killing it with the signal. That is the Nix
  # builder condition `_write_help` exists for. Under the default disposition
  # the SUT dies of SIGPIPE before reaching that branch and every assertion
  # below would hold whether or not the handling is present, so the ignored
  # disposition is the only one worth running.
  #
  # LAST_RC is the SUT's own status, not the pipeline's. With --merge-stderr,
  # fd 1 and fd 2 are the same broken pipe, which is how `usage >&2` lands in
  # the pipe branch, and LAST_OUT holds the one line the reader took before
  # closing; otherwise stderr is captured into LAST_ERR.
  local mode=plain
  if [[ ${1:-} == "--merge-stderr" ]]; then
    mode=merge
    shift
  fi
  LAST_RC=0
  LAST_OUT=""
  LAST_ERR=""
  # WITHGH_BIN is prepended rather than substituted: the wrapper needs `head`,
  # and the stub only has to win over any real `gh` that happens to be present.
  if [[ ${mode} == merge ]]; then
    LAST_OUT="$(PATH="${WITHGH_BIN}:${PATH}" "${BASH_BIN}" -c \
      "${SIGPIPE_WRAPPER}" bash "${mode}" "${BASH_BIN}" "${SUT}" "$@")" || LAST_RC=$?
  else
    LAST_ERR="$(PATH="${WITHGH_BIN}:${PATH}" "${BASH_BIN}" -c \
      "${SIGPIPE_WRAPPER}" bash "${mode}" "${BASH_BIN}" "${SUT}" "$@" 2>&1)" || LAST_RC=$?
  fi
}

assert_parser_accepts() {
  run_without_gh "$@"
  [[ ${LAST_RC} -eq 1 && ${LAST_ERR} == *"required command not found: gh"* ]] ||
    fail "parser rejected documented input '$*' (rc=${LAST_RC}): ${LAST_ERR}"
}

assert_parser_rejects() {
  local needle="$1"
  shift
  run_without_gh "$@"
  [[ ${LAST_RC} -eq 1 && ${LAST_ERR} == *"${needle}"* ]] ||
    fail "expected '${needle}' for '$*' (rc=${LAST_RC}): ${LAST_ERR}"
}

allowlist_keys() {
  # SUBCOMMAND_FLAGS keys straight out of the source, to compare against the
  # subcommands the help document claims exist. Scoped to that declaration so a
  # later associative array with the same key shape cannot join the set.
  local line found=false
  while IFS= read -r line; do
    if [[ ${found} == false ]]; then
      [[ ${line} == 'declare -rA SUBCOMMAND_FLAGS=('* ]] && found=true
      continue
    fi
    [[ ${line} == ')'* ]] && break
    if [[ ${line} =~ ^[[:space:]]*\[\"([a-z-]+)\"\]= ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done <"${SUT}"
  [[ ${found} == true ]] || fail "no SUBCOMMAND_FLAGS declaration in ${SUT}"
}

format_dispatch_arms() {
  # Args: <function-name>
  # Labels of the `case "${OUTPUT_FORMAT}"` arms in the named function, one per
  # line, with a multi-label arm (`text | full | ...`) split into its parts.
  # The catch-all is skipped: it is the error arm, not a format.
  local fn="$1" line found=false in_case=false arm
  while IFS= read -r line; do
    if [[ ${found} == false ]]; then
      [[ ${line} == "${fn}() {"* ]] && found=true
      continue
    fi
    if [[ ${in_case} == false ]]; then
      # shellcheck disable=SC2016 # matches that text in the source, not an expansion
      [[ ${line} == *'case "${OUTPUT_FORMAT}" in'* ]] && in_case=true
      continue
    fi
    [[ ${line} =~ ^[[:space:]]*esac ]] && break
    if [[ ${line} =~ ^[[:space:]]*([a-z][a-z\|[:space:]]*)\) ]]; then
      arm="${BASH_REMATCH[1]// /}"
      printf '%s\n' "${arm//|/$'\n'}"
    fi
  done <"${SUT}"
  [[ ${found} == true ]] || fail "no ${fn} definition in ${SUT}"
  [[ ${in_case} == true ]] || fail "no OUTPUT_FORMAT dispatch in ${fn}"
}

kind_dispatch_arms() {
  # Args: <function-name>
  # Labels of the `case "$1"` arms in a per-kind renderer, one per line. The
  # catch-all is skipped because it is the error arm, not a template.
  local fn="$1" line found=false in_case=false arm
  while IFS= read -r line; do
    if [[ ${found} == false ]]; then
      [[ ${line} == "${fn}() {"* ]] && found=true
      continue
    fi
    if [[ ${in_case} == false ]]; then
      # shellcheck disable=SC2016 # matches that text in the source, not an expansion
      [[ ${line} == *'case "$1" in'* ]] && in_case=true
      continue
    fi
    [[ ${line} =~ ^[[:space:]]*esac ]] && break
    if [[ ${line} =~ ^[[:space:]]*([a-z][a-z\|[:space:]]*)\) ]]; then
      arm="${BASH_REMATCH[1]// /}"
      printf '%s\n' "${arm//|/$'\n'}"
    fi
  done <"${SUT}"
  [[ ${found} == true ]] || fail "no ${fn} definition in ${SUT}"
  [[ ${in_case} == true ]] || fail "no kind dispatch in ${fn}"
}

format_call_kinds() {
  # Literal kind arguments at production call sites. Dynamic forwarding inside
  # the dispatch functions is intentionally excluded: the callers are the
  # ownership boundary that must stay in parity with every per-kind renderer.
  local line
  while IFS= read -r line; do
    [[ ${line} =~ ^[[:space:]]*# ]] && continue
    if [[ ${line} =~ _format_(array|object)[[:space:]]+([a-z-]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[2]}"
    fi
  done <"${SUT}"
}

current_pr_view_fields() {
  # The --json list `current_pr` hands gh, one field per line. Scoped to that
  # function so another `pr view` cannot join the set. The list sits on the
  # line after a `--json \` continuation, so both spellings are handled.
  local line found=false continued=false fields=""
  while IFS= read -r line; do
    if [[ ${found} == false ]]; then
      [[ ${line} == 'current_pr() {'* ]] && found=true
      continue
    fi
    [[ ${line} == '}'* ]] && break
    if [[ ${continued} == true ]]; then
      [[ ${line} =~ ^[[:space:]]*([A-Za-z,]+) ]] || break
      fields+="${BASH_REMATCH[1]}"
      [[ ${line} =~ \\$ ]] || break
    elif [[ ${line} =~ --json[[:space:]]+\\$ ]]; then
      continued=true
    elif [[ ${line} =~ --json[[:space:]]+([A-Za-z,]+) ]]; then
      fields="${BASH_REMATCH[1]}"
      break
    fi
  done <"${SUT}"
  [[ ${found} == true ]] || fail "no current_pr definition in ${SUT}"
  [[ -n ${fields} ]] || fail "no --json field list in current_pr"
  printf '%s\n' "${fields//,/$'\n'}"
}

current_pr_documented_fields() {
  # The `Fields:` run out of current-pr's description, one field per line. It
  # ends at the first period, so prose about those fields can follow.
  local description
  description="$("${SUT}" --help --json |
    jq -r '.subcommandGroups[].subcommands[] | select(.name == "current-pr") | .description[0]')"
  [[ ${description} =~ Fields:[[:space:]]*([^.]+) ]] ||
    fail "current-pr's description carries no 'Fields:' list"
  printf '%s\n' "${BASH_REMATCH[1]//,/$'\n'}" | tr -d ' '
}

current_pr_tsv_columns() {
  # The `current-pr:` row out of --format's tsv column list, one name per line.
  local row
  row="$("${SUT}" --help --json | jq -r '
    .options[] | select(.flags[0].name == "--format") | .description[]
    | select(type == "object") | .text | select(startswith("current-pr:"))
  ')"
  [[ -n ${row} ]] || fail "--format documents no current-pr tsv columns"
  printf '%s\n' "${row#current-pr:}" | tr ',' '\n' | tr -d ' '
}

flatten() {
  # Whitespace-normalized help text. The renderer rewraps every paragraph, so a
  # document string only survives into the text as a run of words.
  tr '\n' ' ' | tr -s ' '
}

test_help_json_is_a_document() {
  local out
  out="$("${SUT}" --help --json)"
  printf '%s' "${out}" | jq empty ||
    fail "--help --json did not emit valid JSON"
  printf '%s' "${out}" | jq -e '
    .name == "pr-comments-mgmt.sh"
    and (.summary | type == "string")
    and (.description | length > 0)
    and (.subcommandGroups | length > 0)
    and (.options | length > 0)
    and (.notes | length > 0)
    and (.exitCodes | length > 0)
    and (.examples | length > 0)
  ' >/dev/null || fail "--help --json is missing required top-level fields"
}

test_json_flag_is_position_independent() {
  local after before short
  after="$("${SUT}" --help --json)"
  before="$("${SUT}" --json --help)"
  short="$("${SUT}" -h --json)"
  [[ ${after} == "${before}" ]] || fail "--json before --help produced different output"
  [[ ${after} == "${short}" ]] || fail "-h --json produced different output than --help --json"
}

test_text_help_covers_the_document() {
  local text json flat item
  text="$("${SUT}" --help)"
  json="$("${SUT}" --help --json)"
  flat="$(printf '%s' "${text}" | flatten)"
  [[ ${text} == "pr-comments-mgmt.sh: "* ]] || fail "help text lost its header line"
  while IFS= read -r item; do
    [[ ${text} == *"  ${item}"* ]] || fail "help text is missing subcommand: ${item}"
  done < <(printf '%s' "${json}" | jq -r '.subcommandGroups[].subcommands[].usage')
  while IFS= read -r item; do
    [[ ${text} == *"${item}"* ]] || fail "help text is missing option: ${item}"
  done < <(printf '%s' "${json}" | jq -r '.options[].flags[].name')
  while IFS= read -r item; do
    [[ ${text} == *"${item}"* ]] || fail "help text is missing example: ${item}"
  done < <(printf '%s' "${json}" | jq -r '.examples[] | split("\n")[0]')
  # Rewrapped sections, so these join against the normalized text: a note is a
  # word run, and an exit code renders as `<code>` then its meaning.
  while IFS= read -r item; do
    item="$(printf '%s' "${item}" | flatten)"
    [[ ${flat} == *"${item}"* ]] || fail "help text is missing note: ${item:0:60}"
  done < <(printf '%s' "${json}" | jq -r '.notes[]')
  while IFS= read -r item; do
    [[ ${flat} == *" ${item}"* ]] || fail "help text is missing exit code: ${item}"
  done < <(printf '%s' "${json}" | jq -r '.exitCodes[] | "\(.code) \(.meaning)"')
}

test_documented_subcommands_match_the_allowlist() {
  local documented enforced
  documented="$("${SUT}" --help --json | jq -r '.subcommandGroups[].subcommands[].name' | sort | tr '\n' ' ')"
  enforced="$(allowlist_keys | sort | tr '\n' ' ')"
  [[ ${documented} == "${enforced}" ]] ||
    fail "documented subcommands (${documented}) differ from SUBCOMMAND_FLAGS keys (${enforced})"
  # allowedOptions names carry the `--` that SUBCOMMAND_FLAGS omits, so they
  # join against .options[].flags[].name without a prefix rule of their own.
  "${SUT}" --help --json | jq -e '
    [.options[].flags[].name] as $documented
    | all(.subcommandGroups[].subcommands[];
          (.allowedOptions | type == "array") and (.allowedOptions | length > 0))
    and ([.subcommandGroups[].subcommands[].allowedOptions[]] - $documented | length == 0)
  ' >/dev/null ||
    fail "a subcommand's allowedOptions is missing or names an undocumented option"
}

test_documented_choices_are_the_enforced_ones() {
  local json flag choice line
  json="$("${SUT}" --help --json)"
  # Every accepted-value list is grafted from the array the parser validates
  # against, so this set changing means an option gained or lost one. Update
  # the list once the new option's values are grafted the same way.
  printf '%s' "${json}" | jq -e '
    ([.options[] | select(has("choices")) | .flags[0].name] | sort)
    == ["--format", "--minimized", "--reason", "--sort"]
  ' >/dev/null || fail "the set of options carrying an accepted-value list changed"
  printf '%s' "${json}" | jq -e '
    all(.options[] | select(has("choices"));
        .flags[0].argument == ("{" + (.choices | join("|")) + "}"))
  ' >/dev/null || fail "an option's displayed argument disagrees with its choices"
  while IFS= read -r line; do
    flag="${line%% *}"
    choice="${line#* }"
    # Both spellings: the parser carries a separate case arm for each.
    assert_parser_accepts "${flag}=${choice}"
    assert_parser_accepts "${flag}" "${choice}"
  done < <(printf '%s' "${json}" |
    jq -r '.options[] | select(has("choices")) | .flags[0].name as $f | .choices[] | "\($f) \(.)"')
  while IFS= read -r flag; do
    assert_parser_rejects "${flag} must be one of" "${flag}=__not_a_choice__"
    assert_parser_rejects "${flag} must be one of" "${flag}" "__not_a_choice__"
  done < <(printf '%s' "${json}" | jq -r '.options[] | select(has("choices")) | .flags[0].name')
}

test_every_documented_format_has_a_renderer() {
  # --format values reach the render dispatch, which is past the API call, so
  # this joins the accepted set against the dispatch in the source instead.
  # Without it a value added to VALID_FORMATS is documented and accepted on the
  # spot while nothing renders it. Both dispatches are checked: the list-* verbs
  # render through _format_array, the single-object verbs through
  # _format_object, and a format handled by only one of them is a subcommand
  # that dies mid-pipe on a documented value.
  local accepted dispatched fn
  accepted="$("${SUT}" --help --json |
    jq -r '.options[] | select(.flags[0].name == "--format") | .choices[]' | sort | tr '\n' ' ')"
  [[ -n ${accepted} ]] || fail "--format carries no choices list"
  for fn in _format_array _format_object; do
    dispatched="$(format_dispatch_arms "${fn}" | sort | tr '\n' ' ')"
    [[ ${accepted} == "${dispatched}" ]] ||
      fail "accepted --format values (${accepted}) differ from ${fn} arms (${dispatched})"
  done
}

test_format_call_kinds_have_templates() {
  # A typo in a literal kind argument reaches the per-kind renderer only for
  # text/full/tsv/body. JSON and ndjson bypass those templates, so the normal
  # current-pr fixture would otherwise leave get-thread/get-comment failures
  # untested. Keep every literal call-site kind in parity with all templates.
  local call_kinds renderer renderer_kinds kind
  call_kinds="$(format_call_kinds | sort -u)"
  [[ -n ${call_kinds} ]] || fail "no literal _format_array/_format_object call-site kinds found"
  for renderer in _format_text _format_full _format_tsv _format_body; do
    renderer_kinds="$(kind_dispatch_arms "${renderer}" | sort -u | tr '\n' ' ')"
    while IFS= read -r kind; do
      [[ -n ${kind} ]] || continue
      [[ " ${renderer_kinds} " == *" ${kind} "* ]] ||
        fail "${renderer} has no template for call-site kind '${kind}'"
    done <<<"${call_kinds}"
  done
}

test_every_read_subcommand_accepts_format() {
  # `--format` is enforced per subcommand out of SUBCOMMAND_FLAGS, which is
  # what grafts allowedOptions into the document. A read verb missing it is
  # rejected at the parser ("--format is not applicable") no matter what its
  # renderer does, which is the shape the single-object verbs shipped in.
  local json read_count missing
  json="$("${SUT}" --help --json)"
  # Counted first: the group is selected by title, so a retitled group would
  # otherwise leave nothing to check and pass on an empty set.
  read_count="$(printf '%s' "${json}" |
    jq '[.subcommandGroups[] | select(.title | test("^Read")) | .subcommands[]] | length')"
  [[ ${read_count} -gt 0 ]] || fail "the help document has no read-subcommand group"
  missing="$(printf '%s' "${json}" | jq -r '
    .subcommandGroups[] | select(.title | test("^Read")) | .subcommands[]
    | select((.allowedOptions | index("--format")) == null) | .name
  ' | tr '\n' ' ')"
  [[ -z ${missing} ]] ||
    fail "read subcommands missing --format from their allowlist: ${missing}"
}

test_current_pr_documents_its_payload() {
  # `current-pr` is read for fields the caller then feeds to something else, so
  # a field dropped from the gh call while the document still advertises it is
  # a null the caller only discovers at use. The payload itself is past the API
  # call, so this joins the two lists in the source instead.
  local documented enforced
  documented="$(current_pr_documented_fields | sort | tr '\n' ' ')"
  enforced="$(current_pr_view_fields | sort | tr '\n' ' ')"
  [[ ${documented} == "${enforced}" ]] ||
    fail "documented current-pr fields (${documented}) differ from the gh --json list (${enforced})"
}

test_current_pr_renders_every_format() {
  # The one payload path a stub can serve end to end, so every --format value
  # is rendered here rather than asserted against the dispatch alone.
  local pr=owner/repo#149 id body default_json line_count
  local fixture_keys requested_fields
  id="$(jq -r '.id' "${PR_VIEW_FIXTURE}")"
  body="$(jq -r '.body' "${PR_VIEW_FIXTURE}")"

  # The stub answers any `pr view` regardless of --json, so this ties the
  # fixture to the field list current_pr requests. Without it, dropping a
  # field from that list still renders the fixture's value here and only
  # turns into an empty live field.
  fixture_keys="$(jq -r 'keys_unsorted[]' "${PR_VIEW_FIXTURE}" | sort | tr '\n' ' ')"
  requested_fields="$(current_pr_view_fields | sort | tr '\n' ' ')"
  [[ ${fixture_keys} == "${requested_fields}" ]] ||
    fail "fixture keys (${fixture_keys}) differ from current-pr's --json list (${requested_fields})"

  # json stays a bare object. `current-pr | jq -r .number` is the reason the
  # verb exists, so the array shape the list-* verbs emit would break callers.
  assert_pr_view_ok "current-pr --format=json" --pr "${pr}" current-pr --format=json
  printf '%s' "${LAST_OUT}" | jq -e '
    type == "object" and .number == 149 and .labels == ["type(fix)", "area(scripts)"]
  ' >/dev/null || fail "current-pr --format=json is not the flattened PR object: ${LAST_OUT}"
  default_json="${LAST_OUT}"

  # --format=json names the default; it is not a second mode.
  assert_pr_view_ok "current-pr (no --format)" --pr "${pr}" current-pr
  [[ ${LAST_OUT} == "${default_json}" ]] ||
    fail "current-pr without --format differs from --format=json"

  assert_pr_view_ok "current-pr --format=ndjson" --pr "${pr}" current-pr --format=ndjson
  line_count="$(printf '%s\n' "${LAST_OUT}" | wc -l)"
  [[ ${line_count} -eq 1 ]] || fail "ndjson emitted ${line_count} lines for one PR"
  [[ "$(printf '%s' "${LAST_OUT}" | jq -Sc .)" == "$(printf '%s' "${default_json}" | jq -Sc .)" ]] ||
    fail "ndjson and json disagree on the document"

  assert_pr_view_ok "current-pr --format=ids" --pr "${pr}" current-pr --format=ids
  [[ ${LAST_OUT} == "${id}" ]] || fail "ids emitted '${LAST_OUT}', expected '${id}'"

  assert_pr_view_ok "current-pr --format=body" --pr "${pr}" current-pr --format=body
  [[ ${LAST_OUT} == "${body}" ]] || fail "body emitted '${LAST_OUT}', expected the PR body"

  assert_pr_view_ok "current-pr --format=text" --pr "${pr}" current-pr --format=text
  line_count="$(printf '%s\n' "${LAST_OUT}" | wc -l)"
  [[ ${line_count} -eq 1 ]] || fail "text emitted ${line_count} lines for one PR"
  [[ ${LAST_OUT} == "${id}"$'\t'* ]] ||
    fail "text is not prefixed with '<id>\\t': ${LAST_OUT}"

  assert_pr_view_ok "current-pr --format=full" --pr "${pr}" current-pr --format=full
  [[ ${LAST_OUT} == "=== ${id} "* ]] ||
    fail "full is missing its '=== <id> ...' header: ${LAST_OUT}"
  [[ ${LAST_OUT} == *"${body}"* ]] || fail "full dropped the PR body"

  # Column count is read off the document, so a column added to the renderer
  # without a document update (or the reverse) fails here. Split through jq:
  # `IFS=$'\t' read -a` treats tab as IFS whitespace, so a run of tabs would
  # collapse and an empty column would go uncounted.
  local expected_columns actual_columns first_column
  assert_pr_view_ok "current-pr --format=tsv" --pr "${pr}" current-pr --format=tsv
  line_count="$(printf '%s\n' "${LAST_OUT}" | wc -l)"
  [[ ${line_count} -eq 1 ]] || fail "tsv emitted ${line_count} lines for one PR"
  actual_columns="$(printf '%s' "${LAST_OUT}" | jq -R 'split("\t") | length')"
  expected_columns="$(current_pr_tsv_columns | wc -l)"
  [[ ${actual_columns} -eq ${expected_columns} ]] ||
    fail "tsv emitted ${actual_columns} columns, document lists ${expected_columns}"
  first_column="$(printf '%s' "${LAST_OUT}" | jq -Rr 'split("\t")[0]')"
  [[ ${first_column} == "${id}" ]] ||
    fail "tsv's first column is '${first_column}', expected the id"

  # Count alone passes on a reordered row. The OID adjacency is the part
  # callers script against (`cut -f8,9` is the diff range), so pin those two
  # positions against the fixture rather than trusting the column total.
  local oid_columns expected_oids
  oid_columns="$(printf '%s' "${LAST_OUT}" | jq -Rr 'split("\t") | .[7:9] | join(" ")')"
  expected_oids="$(jq -r '[.headRefOid, .baseRefOid] | join(" ")' "${PR_VIEW_FIXTURE}")"
  [[ ${oid_columns} == "${expected_oids}" ]] ||
    fail "tsv columns 8,9 are '${oid_columns}', expected head/base OIDs '${expected_oids}'"
}

test_get_thread_full_and_body_render_every_reply() {
  # Regression for the PR #464 review round: routing get-thread through
  # _format_object used to wrap the whole thread object and hand it to the
  # `threads` template, which reads only .comments.nodes[0] -- silently
  # dropping every reply _paginate_thread_comments had just fetched. full and
  # body must now show all three comments; text and tsv are still the
  # one-line list-threads-parity summary and must stay that way.
  local thread_id line_count
  thread_id="$(jq -r '.data.node.id' "${THREAD_FIXTURE}")"

  run_with_thread get-thread "${thread_id}" --format=full
  assert_last_ok "get-thread --format=full"
  [[ ${LAST_OUT} == *"opener-body"* ]] || fail "get-thread --format=full dropped the opener: ${LAST_OUT}"
  [[ ${LAST_OUT} == *"first-reply-body"* ]] || fail "get-thread --format=full dropped a reply: ${LAST_OUT}"
  [[ ${LAST_OUT} == *"second-reply-body"* ]] || fail "get-thread --format=full dropped a reply: ${LAST_OUT}"

  run_with_thread get-thread "${thread_id}" --format=body
  assert_last_ok "get-thread --format=body"
  [[ ${LAST_OUT} == *"opener-body"* ]] || fail "get-thread --format=body dropped the opener: ${LAST_OUT}"
  [[ ${LAST_OUT} == *"first-reply-body"* ]] || fail "get-thread --format=body dropped a reply: ${LAST_OUT}"
  [[ ${LAST_OUT} == *"second-reply-body"* ]] || fail "get-thread --format=body dropped a reply: ${LAST_OUT}"

  run_with_thread get-thread "${thread_id}" --format=text
  assert_last_ok "get-thread --format=text"
  line_count="$(printf '%s\n' "${LAST_OUT}" | wc -l)"
  [[ ${line_count} -eq 1 ]] || fail "get-thread --format=text emitted ${line_count} lines, expected the one-opener summary"
  [[ ${LAST_OUT} == *"comments=3"* ]] || fail "get-thread --format=text lost the comment count: ${LAST_OUT}"

  run_with_thread get-thread "${thread_id}" --format=tsv
  assert_last_ok "get-thread --format=tsv"
  line_count="$(printf '%s\n' "${LAST_OUT}" | wc -l)"
  [[ ${line_count} -eq 1 ]] || fail "get-thread --format=tsv emitted ${line_count} lines, expected the one-opener summary"
  [[ "$(printf '%s' "${LAST_OUT}" | jq -Rr 'split("\t")[6]')" == "3" ]] ||
    fail "get-thread --format=tsv comments column is not 3: ${LAST_OUT}"
}

test_usage_error_goes_to_stderr() {
  # The output convention is diagnostics on stderr, payloads on stdout: a usage
  # error on stdout corrupts `list-threads --format=ids | ... resolve`. Needs
  # the gh stub, since require_cmd now runs before the no-subcommand check.
  run_with_gh
  [[ ${LAST_RC} -eq 1 ]] || fail "no-subcommand run exited ${LAST_RC}, expected 1"
  [[ -z ${LAST_OUT} ]] || fail "usage error wrote to stdout: ${LAST_OUT}"
  [[ ${LAST_ERR} == "pr-comments-mgmt.sh: "* ]] ||
    fail "usage text missing from stderr: ${LAST_ERR}"
}

test_json_flag_requires_help() {
  local invocation
  for invocation in "--json" "--json list-threads"; do
    # shellcheck disable=SC2086 # the fixture supplies its own word split
    run_without_gh ${invocation}
    [[ ${LAST_RC} -eq 1 ]] || fail "'${invocation}' exited ${LAST_RC}, expected 1"
    [[ ${LAST_ERR} == *"--json is only supported with -h/--help"* ]] ||
      fail "'${invocation}' did not explain the --json restriction: ${LAST_ERR}"
    [[ -z ${LAST_OUT} ]] || fail "'${invocation}' wrote to stdout"
  done
}

test_help_needs_no_gh() {
  run_without_gh --help --json
  [[ ${LAST_RC} -eq 0 ]] || fail "--help --json failed without gh on PATH: ${LAST_ERR}"
  printf '%s' "${LAST_OUT}" | jq -e '.name == "pr-comments-mgmt.sh"' >/dev/null ||
    fail "--help --json emitted no document without gh on PATH"
  run_without_gh current-pr
  [[ ${LAST_RC} -eq 1 && ${LAST_ERR} == *"required command not found: gh"* ]] ||
    fail "a subcommand ran without gh (rc=${LAST_RC}): ${LAST_ERR}"
}

test_help_tolerates_a_closed_reader() {
  # `--help | head` is how help gets read. Losing the tail of the payload is
  # fine; an ERR-trap fatal record on stderr, or a nonzero status, is not.
  # Repeated because the write can win the race against head's exit, in which
  # case the run never reaches the broken-pipe branch at all.
  local args
  for args in "--help" "--help --json"; do
    for _attempt in 1 2 3 4 5; do
      # shellcheck disable=SC2086 # the fixture supplies its own word split
      run_piped_sigpipe_ignored ${args}
      [[ -z ${LAST_ERR} ]] || fail "'${args} | head' emitted diagnostics: ${LAST_ERR}"
      [[ ${LAST_RC} -eq 0 ]] || fail "'${args} | head' exited ${LAST_RC}, expected 0"
    done
  done
}

test_usage_error_keeps_its_status_through_a_closed_reader() {
  # `<sut> 2>&1 | head` puts the usage text on the same broken pipe as stdout,
  # so the truncated write and the successful one have to agree on the status a
  # wrapper sees. Both must be 1: a usage error, not a help request.
  local _attempt
  for _attempt in 1 2 3 4 5; do
    run_piped_sigpipe_ignored --merge-stderr
    # The header proves the run reached `usage`. Without it a status of 1 could
    # equally be `require_cmd gh` firing first, which asserts nothing.
    [[ ${LAST_OUT} == "pr-comments-mgmt.sh: "* ]] ||
      fail "no-subcommand run did not reach usage, first line was: ${LAST_OUT}"
    [[ ${LAST_RC} -eq 1 ]] ||
      fail "no-subcommand usage error through '2>&1 | head' exited ${LAST_RC}, expected 1"
  done
}

tests=(
  test_help_json_is_a_document
  test_json_flag_is_position_independent
  test_text_help_covers_the_document
  test_documented_subcommands_match_the_allowlist
  test_documented_choices_are_the_enforced_ones
  test_every_documented_format_has_a_renderer
  test_format_call_kinds_have_templates
  test_every_read_subcommand_accepts_format
  test_current_pr_documents_its_payload
  test_current_pr_renders_every_format
  test_get_thread_full_and_body_render_every_reply
  test_json_flag_requires_help
  test_help_needs_no_gh
  test_help_tolerates_a_closed_reader
  test_usage_error_goes_to_stderr
  test_usage_error_keeps_its_status_through_a_closed_reader
)

for test_case in "${tests[@]}"; do
  "${test_case}"
done

printf '%d passed\n' "${#tests[@]}"
