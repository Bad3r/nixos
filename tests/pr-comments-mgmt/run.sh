#!/usr/bin/env bash
# shellcheck shell=bash
# Covers the help surface only: every other path reaches the GitHub API, so
# these cases stop at the first argument the parser rejects or at the missing
# `gh` binary, and never open a socket.
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
  # Labels of the `case "${OUTPUT_FORMAT}"` arms in _format_array, to compare
  # against the values the parser accepts. The catch-all is skipped: it is the
  # error arm, not a format.
  local line found=false
  while IFS= read -r line; do
    if [[ ${found} == false ]]; then
      # shellcheck disable=SC2016 # matches that text in the source, not an expansion
      [[ ${line} == *'case "${OUTPUT_FORMAT}" in'* ]] && found=true
      continue
    fi
    [[ ${line} =~ ^[[:space:]]*esac ]] && break
    if [[ ${line} =~ ^[[:space:]]*([a-z|]+)\) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]//|/$'\n'}"
    fi
  done <"${SUT}"
  [[ ${found} == true ]] || fail "no OUTPUT_FORMAT dispatch in ${SUT}"
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
      [[ ${line} =~ ^[[:space:]]*([A-Za-z,]+) ]] && fields="${BASH_REMATCH[1]}"
      break
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
  # --format values reach _format_array, which is past the API call, so this
  # joins the accepted set against the dispatch in the source instead. Without
  # it a value added to VALID_FORMATS is documented and accepted on the spot
  # while nothing renders it.
  local accepted dispatched
  accepted="$("${SUT}" --help --json |
    jq -r '.options[] | select(.flags[0].name == "--format") | .choices[]' | sort | tr '\n' ' ')"
  dispatched="$(format_dispatch_arms | sort | tr '\n' ' ')"
  [[ -n ${accepted} ]] || fail "--format carries no choices list"
  [[ ${accepted} == "${dispatched}" ]] ||
    fail "accepted --format values (${accepted}) differ from _format_array arms (${dispatched})"
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
  test_current_pr_documents_its_payload
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
