#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../../scripts/run-packages-updaters.sh"

if [[ ! -x ${SUT} ]]; then
  printf 'run.sh: SUT not executable at %s\n' "${SUT}" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    chmod -R u+w "${tmpdir}"
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

tests_passed=0

pass() {
  tests_passed=$((tests_passed + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [[ -n ${2:-} && -f ${2:-} ]]; then
    printf '%s\n' '--- SUT output ---' >&2
    cat "$2" >&2
    printf '%s\n' '------------------' >&2
  fi
  exit 1
}

make_fixture() {
  fixture_root="${tmpdir}/$1"
  mkdir -p "${fixture_root}/scripts"
  cp "${SUT}" "${fixture_root}/scripts/run-packages-updaters.sh"
  chmod +x "${fixture_root}/scripts/run-packages-updaters.sh"
}

run_sut() {
  local err out
  out="$1"
  err="$2"
  shift 2
  if "${fixture_root}/scripts/run-packages-updaters.sh" "$@" >"${out}" 2>"${err}"; then
    sut_status=0
  else
    sut_status=$?
  fi
}

assert_contains() {
  local file pattern label
  file="$1"
  pattern="$2"
  label="$3"
  grep -Fq -- "${pattern}" "${file}" ||
    fail "${label}: output does not contain '${pattern}'" "${file}"
}

assert_not_contains() {
  local file pattern label
  file="$1"
  pattern="$2"
  label="$3"
  if grep -Fq -- "${pattern}" "${file}"; then
    fail "${label}: output unexpectedly contains '${pattern}'" "${file}"
  fi
}

assert_empty() {
  local file label
  file="$1"
  label="$2"
  [[ ! -s ${file} ]] || fail "${label}: output was not empty" "${file}"
}

write_updater() {
  local name label status updater
  name="$1"
  label="$2"
  status="$3"
  updater="${fixture_root}/packages/${name}/update.py"

  mkdir -p "$(dirname "${updater}")"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    "printf '%s\\n' '${label}' >> \"\${RUN_LOG}\"" \
    "exit ${status}" >"${updater}"
  chmod +x "${updater}"
}

test_help_exits_before_discovery() {
  local err out
  make_fixture help
  out="${tmpdir}/help.out"
  err="${tmpdir}/help.err"
  run_sut "${out}" "${err}" --help

  [[ ${sut_status} -eq 0 ]] || fail "help: expected exit 0, got ${sut_status}" "${err}"
  assert_contains "${out}" 'Usage: run-packages-updaters.sh [-h|--help]' 'help'
  assert_not_contains "${out}" 'No package updaters found' 'help'
  assert_empty "${err}" 'help stderr'
  pass
}

test_rejects_unknown_argument() {
  local err out
  make_fixture unknown
  out="${tmpdir}/unknown.out"
  err="${tmpdir}/unknown.err"
  run_sut "${out}" "${err}" --unexpected

  [[ ${sut_status} -eq 2 ]] || fail "unknown: expected exit 2, got ${sut_status}" "${err}"
  assert_empty "${out}" 'unknown stdout'
  assert_contains "${err}" 'Usage: run-packages-updaters.sh [-h|--help]' 'unknown'
  pass
}

test_rejects_extra_help_argument() {
  local err out
  make_fixture extra-help
  out="${tmpdir}/extra-help.out"
  err="${tmpdir}/extra-help.err"
  run_sut "${out}" "${err}" --help extra

  [[ ${sut_status} -eq 2 ]] || fail "extra-help: expected exit 2, got ${sut_status}" "${err}"
  assert_empty "${out}" 'extra-help stdout'
  assert_contains "${err}" 'Usage: run-packages-updaters.sh [-h|--help]' 'extra-help'
  pass
}

test_empty_package_root_fails() {
  local err expected out
  make_fixture empty
  out="${tmpdir}/empty.out"
  err="${tmpdir}/empty.err"
  expected="No package updaters found under ${fixture_root}/packages."
  run_sut "${out}" "${err}"

  [[ ${sut_status} -eq 1 ]] || fail "empty: expected exit 1, got ${sut_status}" "${err}"
  assert_empty "${out}" 'empty stdout'
  assert_contains "${err}" "${expected}" 'empty'
  pass
}

test_stops_after_first_failure() {
  local actual err out
  make_fixture fail-fast
  export RUN_LOG="${fixture_root}/run.log"
  write_updater 01-first first 0
  write_updater 02-failing second 7
  write_updater 03-unreached third 0
  out="${tmpdir}/fail-fast.out"
  err="${tmpdir}/fail-fast.err"
  run_sut "${out}" "${err}"

  [[ ${sut_status} -eq 7 ]] || fail "fail-fast: expected exit 7, got ${sut_status}" "${err}"
  assert_contains "${out}" 'Package updaters: 3' 'fail-fast'
  assert_contains "${err}" 'failed with exit code 7' 'fail-fast'
  [[ -f ${RUN_LOG} ]] || fail 'fail-fast: updater log was not created' "${out}"
  actual="$(<"${RUN_LOG}")"
  [[ ${actual} == $'first\nsecond' ]] ||
    fail "fail-fast: expected first and second updaters only, got '${actual}'" "${out}"
  assert_not_contains "${out}" '03-unreached' 'fail-fast'
  pass
}

test_help_exits_before_discovery
test_rejects_unknown_argument
test_rejects_extra_help_argument
test_empty_package_root_fails
test_stops_after_first_failure

printf '%d passed\n' "${tests_passed}"
