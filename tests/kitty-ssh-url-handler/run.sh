#!/usr/bin/env bash
# shellcheck shell=bash
# Exercises the packaged ssh:// parser with deterministic Kitty and
# notification stubs. The stubs record NUL-delimited argv so argument
# boundaries remain observable.
set -euo pipefail
export LC_ALL=C

SUT="${KITTY_SSH_URL_HANDLER:-}"
if [[ -z ${SUT} ]] && ! SUT="$(command -v kitty-ssh-url-handler)"; then
  SUT=""
fi

if [[ -z ${SUT} || ! -x ${SUT} ]]; then
  printf 'run.sh: kitty-ssh-url-handler is not on PATH; build the script-tests check or set KITTY_SSH_URL_HANDLER\n' >&2
  exit 2
fi

package_root="$(dirname "$(dirname "${SUT}")")"
desktop_file="${package_root}/share/applications/kitty-ssh-url-handler.desktop"
tmpdir="$(mktemp -d)"

cleanup() {
  if [[ -d ${tmpdir} ]]; then
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

export KITTY_SSH_KITTY_LOG="${tmpdir}/kitty.argv"
export KITTY_SSH_NOTIFY_LOG="${tmpdir}/notify.argv"

tests_passed=0
handler_rc=0

pass() {
  tests_passed=$((tests_passed + 1))
}

fail() {
  local message="$1"

  printf 'FAIL: %s\n' "${message}" >&2
  if [[ -s ${tmpdir}/stderr ]]; then
    printf '%s\n' '--- handler stderr ---' >&2
    cat "${tmpdir}/stderr" >&2
    printf '%s\n' '----------------------' >&2
  fi
  exit 1
}

reset_run() {
  : >"${KITTY_SSH_KITTY_LOG}"
  : >"${KITTY_SSH_NOTIFY_LOG}"
  : >"${tmpdir}/stdout"
  : >"${tmpdir}/stderr"
  handler_rc=0
}

run_handler() {
  reset_run
  "${SUT}" "$@" >"${tmpdir}/stdout" 2>"${tmpdir}/stderr" || handler_rc=$?
}

format_argv() {
  local -a argv=("$@")
  local arg

  for arg in "${argv[@]}"; do
    printf ' <%q>' "${arg}"
  done
}

assert_argv() {
  local label="$1"
  local log="$2"
  shift 2
  local -a expected=("$@")
  local -a actual=()
  local i

  mapfile -d '' -t actual <"${log}"
  if [[ ${#actual[@]} -ne ${#expected[@]} ]]; then
    printf 'expected argv:' >&2
    format_argv "${expected[@]}" >&2
    printf '\nactual argv:' >&2
    format_argv "${actual[@]}" >&2
    printf '\n' >&2
    fail "${label}: expected ${#expected[@]} arguments, got ${#actual[@]}"
  fi
  for ((i = 0; i < ${#expected[@]}; i++)); do
    if [[ ${actual[i]} != "${expected[i]}" ]]; then
      printf 'expected argv:' >&2
      format_argv "${expected[@]}" >&2
      printf '\nactual argv:' >&2
      format_argv "${actual[@]}" >&2
      printf '\n' >&2
      fail "${label}: argument ${i} differs"
    fi
  done
}

assert_accept() {
  local label="$1"
  local url="$2"
  shift 2

  run_handler "${url}"
  [[ ${handler_rc} -eq 0 ]] || fail "${label}: expected exit 0, got ${handler_rc}"
  [[ ! -s ${tmpdir}/stdout ]] || fail "${label}: accepted URL wrote to stdout"
  [[ ! -s ${tmpdir}/stderr ]] || fail "${label}: accepted URL wrote to stderr"
  assert_argv "${label}: Kitty" "${KITTY_SSH_KITTY_LOG}" "$@"
  [[ ! -s ${KITTY_SSH_NOTIFY_LOG} ]] || fail "${label}: accepted URL attempted a rejection notification"
  pass
}

assert_reject() {
  local label="$1"
  local reason="$2"
  local context="$3"
  shift 3
  local message="${reason}"

  if [[ -n ${context} ]]; then
    message="${reason}: ${context}"
  fi

  run_handler "$@"
  [[ ${handler_rc} -eq 1 ]] || fail "${label}: expected exit 1, got ${handler_rc}"
  [[ ! -s ${tmpdir}/stdout ]] || fail "${label}: rejected URL wrote to stdout"
  [[ ! -s ${KITTY_SSH_KITTY_LOG} ]] || fail "${label}: rejected URL invoked Kitty"
  grep -q -F -- "kitty-ssh-url-handler: ${message}" "${tmpdir}/stderr" ||
    fail "${label}: stderr lacks the parser rejection"
  assert_argv "${label}: notification" "${KITTY_SSH_NOTIFY_LOG}" \
    -u critical "Kitty SSH URL rejected" "${message}"
  pass
}

assert_desktop_entry() {
  local exec_line exec_value exec_path

  [[ -f ${desktop_file} ]] || fail "desktop entry is missing at ${desktop_file}"
  grep -q -x -F 'MimeType=x-scheme-handler/ssh' "${desktop_file}" ||
    fail "desktop entry lacks the SSH scheme MIME type"
  grep -q -x -F 'Terminal=false' "${desktop_file}" ||
    fail "desktop entry does not set Terminal=false"
  grep -q -x -F 'NoDisplay=true' "${desktop_file}" ||
    fail "desktop entry does not set NoDisplay=true"
  grep -q -x -F 'Icon=kitty' "${desktop_file}" ||
    fail "desktop entry does not use the Kitty icon"

  exec_line=""
  if ! exec_line="$(grep -x -E 'Exec=.* %u' "${desktop_file}")"; then
    exec_line=""
  fi
  [[ -n ${exec_line} ]] || fail "desktop entry lacks an Exec path followed by %u"
  exec_value="${exec_line#Exec=}"
  exec_path="${exec_value% %u}"
  [[ ${exec_path} == /nix/store/*/bin/kitty-ssh-url-handler ]] ||
    fail "desktop Exec is not an absolute Nix store handler path: ${exec_value}"
  [[ -x ${exec_path} ]] || fail "desktop Exec target is not executable: ${exec_path}"
  [[ $(readlink -f "${exec_path}") == "$(readlink -f "${SUT}")" ]] ||
    fail "desktop Exec does not resolve to the packaged handler"
  [[ ${exec_value} != 'kitty-ssh-url-handler %u' ]] ||
    fail "desktop Exec still depends on a bare PATH lookup"
  pass
}

assert_accept "bare host" "ssh://host" \
  --hold kitten ssh -- host
assert_accept "username" "ssh://user@host" \
  --hold kitten ssh -- user@host
assert_accept "five-digit port 10000" "ssh://host:10000" \
  --hold kitten ssh -p 10000 -- host
assert_accept "five-digit port 22000" "ssh://user@host:22000" \
  --hold kitten ssh -p 22000 -- user@host
assert_accept "maximum port" "ssh://host:65535" \
  --hold kitten ssh -p 65535 -- host
assert_accept "discarded ordinary path" "ssh://host/srv/project" \
  --hold kitten ssh -- host
assert_accept "discarded encoded path" "ssh://host/srv/my%20directory/%40%3A" \
  --hold kitten ssh -- host

shell_marker="${tmpdir}/path-was-executed"
shell_url="ssh://host/\$(touch ${shell_marker});printf-shell-syntax"
assert_accept "discarded shell syntax" "${shell_url}" \
  --hold kitten ssh -- host
[[ ! -e ${shell_marker} ]] || fail "discarded path shell syntax was executed"

assert_reject "zero arguments" \
  "expected exactly one ssh:// URL argument" ""
assert_reject "multiple arguments" \
  "expected exactly one ssh:// URL argument" "ssh://host" \
  "ssh://host" "ssh://other"
assert_reject "non-SSH scheme" \
  "not an ssh:// URL" "https://host" \
  "https://host"
assert_reject "empty authority" \
  "missing host" "ssh://" \
  "ssh://"
assert_reject "path without authority" \
  "missing host" "ssh:///srv/path" \
  "ssh:///srv/path"
assert_reject "empty username" \
  "missing user before '@'" "ssh://@host" \
  "ssh://@host"
assert_reject "bracketed IPv6" \
  "bracketed IPv6 literals are not supported" "ssh://[2001:db8::1]" \
  "ssh://[2001:db8::1]"
assert_reject "multiple at delimiters" \
  "malformed authority" "ssh://user@other@host" \
  "ssh://user@other@host"
assert_reject "multiple colon delimiters" \
  "malformed host:port" "ssh://host:22:33" \
  "ssh://host:22:33"
assert_reject "leading-hyphen username" \
  "user must not start with '-'" "ssh://-user@host" \
  "ssh://-user@host"
assert_reject "leading-hyphen host" \
  "host must not start with '-'" "ssh://-host" \
  "ssh://-host"
assert_reject "invalid username characters" \
  "user has invalid characters" "ssh://bad!user@host" \
  "ssh://bad!user@host"
assert_reject "invalid hostname characters" \
  "host has invalid characters" "ssh://bad!host" \
  "ssh://bad!host"
assert_reject "encoded username" \
  "percent-encoded authority is rejected" "ssh://us%65r@host/path" \
  "ssh://us%65r@host/path"
assert_reject "encoded host" \
  "percent-encoded authority is rejected" "ssh://ho%73t/path" \
  "ssh://ho%73t/path"
assert_reject "encoded port" \
  "percent-encoded authority is rejected" "ssh://host:22%30/path" \
  "ssh://host:22%30/path"
assert_reject "empty port" \
  "missing port after ':'" "ssh://host:" \
  "ssh://host:"
assert_reject "nonnumeric port" \
  "port must be numeric" "ssh://host:abc" \
  "ssh://host:abc"
assert_reject "leading-zero port" \
  "port must not have a leading zero" "ssh://host:022" \
  "ssh://host:022"
assert_reject "zero port" \
  "port out of range" "ssh://host:0" \
  "ssh://host:0"
assert_reject "port above 65535" \
  "port out of range" "ssh://host:65536" \
  "ssh://host:65536"
assert_reject "six-digit port" \
  "port out of range" "ssh://host:100000" \
  "ssh://host:100000"

export KITTY_SSH_NOTIFY_FAIL=1
run_handler "https://host"
unset KITTY_SSH_NOTIFY_FAIL
[[ ${handler_rc} -eq 1 ]] || fail "notification failure: rejection changed to exit ${handler_rc}"
[[ ! -s ${KITTY_SSH_KITTY_LOG} ]] || fail "notification failure: rejected URL invoked Kitty"
grep -q -F -- 'kitty-ssh-url-handler: not an ssh:// URL: https://host' "${tmpdir}/stderr" ||
  fail "notification failure: original parser diagnostic is missing"
grep -q -F -- 'kitty-ssh-url-handler: notify-send failed while reporting rejection' "${tmpdir}/stderr" ||
  fail "notification failure: delivery failure is not logged"
assert_argv "notification failure: attempted notification" "${KITTY_SSH_NOTIFY_LOG}" \
  -u critical "Kitty SSH URL rejected" "not an ssh:// URL: https://host"
pass

assert_desktop_entry

printf '%d passed\n' "${tests_passed}"
