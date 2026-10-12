#!/usr/bin/env bash
set -euo pipefail

subject=$(command -v duplicati-r2-generator-test-subject)
test_root=$(mktemp -d)
trap 'rm -r "$test_root"' EXIT
mkdir -p "$test_root/bin"

# Redirect runtime units and systemctl without touching the host's systemd.
# The test directory variable expands when the generated script runs.
# shellcheck disable=SC2016
sed -e '/^export PATH=/d' \
  -e 's|unit_dir=/run/systemd/system|unit_dir="${DUPLICATI_R2_TEST_UNIT_DIR:?}"|' \
  "$subject" >"$test_root/generator.sh"
printf '#!%s\n' "$(command -v bash)" >"$test_root/bin/systemctl"
cat >>"$test_root/bin/systemctl" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >> "${DUPLICATI_R2_TEST_SYSTEMCTL_LOG:?}"
EOF
chmod +x "$test_root/bin/systemctl"
export PATH="$test_root/bin:$PATH"

run_case() {
  local name=$1 manifest=$2 expected_status=$3 expected_timers=$4 diagnostic=$5
  local case_dir="$test_root/$name" status=0 timers
  mkdir -p "$case_dir/units"
  : >"$case_dir/units/duplicati-r2-backup-stale.timer"
  : >"$case_dir/systemctl.log"
  if [[ $manifest != missing ]]; then
    printf '%s' "$manifest" >"$case_dir/manifest.json"
  fi
  DUPLICATI_R2_CONFIG_SOURCE="$case_dir/manifest.json" \
    DUPLICATI_R2_CONFIG_DEST="$case_dir/manifest.json" \
    DUPLICATI_R2_BACKUP_EXEC=/bin/false \
    DUPLICATI_R2_VERIFY_EXEC=/bin/false \
    DUPLICATI_R2_DEFAULT_STATE_DIR="$case_dir/state" \
    DUPLICATI_R2_TEST_UNIT_DIR="$case_dir/units" \
    DUPLICATI_R2_TEST_SYSTEMCTL_LOG="$case_dir/systemctl.log" \
    bash "$test_root/generator.sh" >"$case_dir/stdout" 2>"$case_dir/stderr" || status=$?
  if [[ $status -ne $expected_status ]]; then
    printf '%s: expected status %s, got %s\n' "$name" "$expected_status" "$status" >&2
    cat "$case_dir/stderr" >&2
    exit 1
  fi
  shopt -s nullglob
  timers=("$case_dir/units/duplicati-r2-backup-"*.timer)
  shopt -u nullglob
  [[ ${#timers[@]} -eq $expected_timers ]]
  [[ ! -e $case_dir/units/duplicati-r2-backup-stale.timer ]]
  grep -Fxq 'daemon-reload' "$case_dir/systemctl.log"
  if [[ -n $diagnostic ]]; then
    grep -Fq "$diagnostic" "$case_dir/stderr"
  fi
  if [[ $expected_timers -gt 0 ]]; then
    grep -Fxq 'enable --runtime duplicati-r2-backup-active.timer' "$case_dir/systemctl.log"
    grep -Fxq 'start duplicati-r2-backup-active.timer' "$case_dir/systemctl.log"
  elif grep -Eq '^(enable|start) ' "$case_dir/systemctl.log"; then
    printf '%s: unexpectedly enabled or started a timer\n' "$name" >&2
    exit 1
  fi
  printf 'PASS %s\n' "$name"
}

run_case all-disabled '{"targets":{"a":{"enable":false},"b":{"enable":false}}}' 0 0 'all targets explicitly disabled'
run_case empty-targets '{"targets":{}}' 1 0 'generated zero backup timers'
run_case absent-targets '{}' 1 0 'generated zero backup timers'
run_case missing-manifest missing 1 0 'missing or empty'
run_case empty-manifest '' 1 0 'missing or empty'
run_case enabled-without-schedule '{"targets":{"active":{"enable":true}}}' 1 0 'generated zero backup timers'
run_case implicit-without-schedule '{"targets":{"active":{}}}' 1 0 'generated zero backup timers'
run_case mixed-without-schedule '{"targets":{"paused":{"enable":false},"active":{}}}' 1 0 'generated zero backup timers'
run_case enabled '{"targets":{"active":{"enable":true,"onCalendar":"daily"}}}' 0 1 ''
run_case implicit-enabled '{"targets":{"active":{"onCalendar":"daily"}}}' 0 1 ''
run_case mixed '{"targets":{"paused":{"enable":false},"active":{"onCalendar":"daily"}}}' 0 1 ''
