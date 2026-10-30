#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject="$repo_root/scripts/duplicati-r2-repair.sh"
real_cli=$(command -v duplicati-cli)
producer=$(command -v duplicati-r2-backup-test-subject)
test_root=$(mktemp -d)
trap 'rm -r "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/home" "$test_root/tmp" "$test_root/state" "$test_root/source"
printf 'synthetic backup contents\n' >"$test_root/source/file.txt"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -n ${DUPLICATI_R2_TEST_ARTIFACT_DIR:-} ]]; then
    mkdir -p "$DUPLICATI_R2_TEST_ARTIFACT_DIR"
    cp -r "$test_root/." "$DUPLICATI_R2_TEST_ARTIFACT_DIR/"
  fi
  exit 1
}

# Only the root check is bypassed in this fixture; verify a reversible one-line
# substitution so a moved guard cannot accidentally weaken unrelated behavior.
# shellcheck disable=SC2016
guard='if [[ ${EUID:-$(id -u)} -ne 0 ]]; then'
[[ $(grep -Fxc "$guard" "$subject") == 1 ]] || fail 'root guard changed'
# shellcheck disable=SC2016
sed 's/^if \[\[ ${EUID:-$(id -u)} -ne 0 \]\]; then$/if false; then # test-only root guard/' \
  "$subject" >"$test_root/repair.sh"
# shellcheck disable=SC2016
sed 's/^if false; then # test-only root guard$/if [[ ${EUID:-$(id -u)} -ne 0 ]]; then/' \
  "$test_root/repair.sh" >"$test_root/reversed.sh"
cmp "$subject" "$test_root/reversed.sh"

printf '#!%s\n' "$(command -v bash)" >"$test_root/bin/duplicati-cli"
cat >>"$test_root/bin/duplicati-cli" <<'CLI'
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >>"${TEST_CALLS:?}"
if [[ $1 == list-broken-files ]]; then
  exit "${TEST_LIST_STATUS:-0}"
elif [[ $1 == purge-broken-files ]]; then
  exit "${TEST_PURGE_STATUS:-0}"
fi
CLI
chmod +x "$test_root/bin/duplicati-cli"

# The generated producer hardcodes its CLI store path. Redirect just that call,
# preserving its destination/database construction and runtime PATH verbatim.
producer_call='/[^ ]*/bin/duplicati-cli "\$@" \|\| rc=\$\?'
[[ $(grep -Ec "^$producer_call$" "$producer") == 1 ]] || fail 'producer CLI call changed'
sed -E "s#^$producer_call\$#\"\${DUPLICATI_R2_TEST_CLI:?}\" \"\$@\" || rc=\$?#" \
  "$producer" >"$test_root/backup.sh"

write_env() {
  cat >"$test_root/credentials" <<'ENV'
AWS_ACCESS_KEY_ID=synthetic-key
AWS_SECRET_ACCESS_KEY=synthetic-secret
DUPLICATI_PASSPHRASE=synthetic-passphrase
ENV
  printf '%s\n' "$@" >>"$test_root/credentials"
}

write_manifest() {
  jq -n --arg root "$test_root" --argjson target "$1" '{
    environmentFile: ($root + "/credentials"), bucket: "test-bucket",
    hostname: "test-host", stateDir: ($root + "/state"),
    targets: {photos: ({path: ($root + "/source")} + $target)}
  }' >"$test_root/config.json"
}

run_subject() {
  local expected=$1
  shift
  : >"$test_root/calls"
  local status=0
  env -i PATH="$test_root/bin:$PATH" HOME="$test_root/home" TMPDIR="$test_root/tmp" \
    TEST_CALLS="$test_root/calls" TEST_LIST_STATUS="${list_status:-0}" TEST_PURGE_STATUS="${purge_status:-0}" \
    DUPLICATI_R2_CONFIG="$test_root/config.json" \
    bash "$test_root/repair.sh" "$@" >"$test_root/stdout" 2>"$test_root/stderr" || status=$?
  if [[ $status != "$expected" ]]; then
    cat "$test_root/stdout" "$test_root/stderr" >&2
    fail "expected status $expected, got $status: $*"
  fi
  [[ -z $(ls -A "$test_root/tmp") ]] || fail 'temporary file leaked'
}

assert_calls() {
  jq -se "$1" "$test_root/calls" >/dev/null || {
    cat "$test_root/calls" >&2
    fail "argv assertion: $1"
  }
}

assert_destination() {
  local host=$1 subpath=${2:-photos}
  local expected="s3://test-bucket/test-host/$subpath?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio&s3-server-name=$host"
  jq -se --arg dest "$expected" --arg db "--dbpath=$test_root/state/duplicati-r2-photos.sqlite" \
    'length == 1 and .[0][1] == $dest and .[0][2] == $db' "$test_root/calls" >/dev/null || fail 'destination/database mismatch'
}

# The original guard runs separately, without the fixture substitution.
if [[ $EUID -ne 0 ]]; then
  status=0
  env -i PATH="$test_root/bin:$PATH" HOME="$test_root/home" TEST_CALLS="$test_root/calls" \
    bash "$subject" photos >"$test_root/stdout" 2>"$test_root/stderr" || status=$?
  [[ $status == 77 ]] || fail 'original nonroot guard did not return 77'
  grep -Fq 'must be run as root' "$test_root/stderr"
else
  fail 'run this suite as a nonroot user to cover the original root guard'
fi
env -i PATH="$test_root/bin:$PATH" bash "$subject" --help >"$test_root/help"
grep -Fq 'parameter files' "$test_root/help"
status=0
env -i PATH="$test_root/bin:$PATH" bash "$subject" --invalid >"$test_root/stdout" 2>"$test_root/stderr" || status=$?
[[ $status == 64 ]] || fail 'argument error did not return 64'

write_env R2_ACCOUNT_ID=test-account
for target in '{}' '{"extraArgs":null}' '{"extraArgs":[]}'; do
  write_manifest "$target"
  run_subject 0 photos
  assert_destination test-account.r2.cloudflarestorage.com
  assert_calls '.[0] | length == 3'
done
printf 'PASS extraArgs defaults and account endpoint\n'

for value in false true '"string"' '{}' 42 '[false]' '[null]' '[{}]' '[1]' '["ok",false]' '["nul\u0000value"]'; do
  write_manifest "{\"extraArgs\":$value}"
  run_subject 78 --purge-broken-files photos
  [[ ! -s $test_root/calls ]] || fail "CLI invoked for invalid extraArgs $value"
  grep -Fq "invalid extraArgs for target 'photos'" "$test_root/stderr"
done
printf 'PASS malformed extraArgs fails before every CLI call\n'

write_manifest '{"extraArgs":["--exclude=*.tmp","--InClUdE=*.txt","--exclude","--exclude-empty-folders=true","--s3-storage-class=STANDARD","","--label=one\ntwo\n","--quoted=\"*.txt\""]}'
run_subject 0 photos
assert_calls '.[0][3:] == ["--exclude=*.tmp","--InClUdE=*.txt","--exclude","--exclude-empty-folders=true","--s3-storage-class=STANDARD","--label=one\ntwo\n","--quoted=\"*.txt\""]'
run_subject 0 --list-broken-files photos -- --dry-run '--include=explicit' --parameters-file=fixture.txt
assert_calls 'length == 1 and .[0][0] == "list-broken-files" and .[0][3:] == ["--exclude-empty-folders=true","--s3-storage-class=STANDARD","--label=one\ntwo\n","--quoted=\"*.txt\"","--dry-run","--include=explicit","--parameters-file=fixture.txt","--console-log-level=Warning"]'
run_subject 0 --purge-broken-files photos -- --dry-run
assert_calls 'length == 2 and .[0][0] == "list-broken-files" and .[1][0] == "purge-broken-files" and .[0][1:] == .[1][1:] and (.[0] | index("--dry-run")) != null and (.[0] | index("--exclude=*.tmp")) == null'
list_status=42 run_subject 42 --purge-broken-files photos
assert_calls 'length == 1 and .[0][0] == "list-broken-files"'
purge_status=43 run_subject 43 --purge-broken-files photos
assert_calls 'length == 2 and .[1][0] == "purge-broken-files"'
printf 'PASS operation arguments, boundaries, and purge preflight failure\n'

write_manifest '{}'
for endpoint in \
  'R2_S3_ENDPOINT=explicit.example|explicit.example' \
  'R2_S3_ENDPOINT_URL=https://url.example|url.example' \
  'R2_S3_ENDPOINT_URL=http://url.example|url.example' \
  'AWS_ENDPOINT_URL=https://aws.example|aws.example'; do
  write_env "${endpoint%%|*}"
  run_subject 0 photos
  assert_destination "${endpoint#*|}"
done
write_env
run_subject 78 photos
[[ ! -s $test_root/calls ]] || fail 'CLI invoked without endpoint'
grep -Fq 'R2 endpoint missing' "$test_root/stderr"
write_env R2_S3_ENDPOINT_URL=https://
run_subject 78 photos
[[ ! -s $test_root/calls ]] || fail 'CLI invoked with empty URL host'
printf 'PASS URL endpoint fallbacks and unresolved endpoint rejection\n'

# Execute the evaluated producer against identical fixtures. This comparison
# observes producer precedence rather than duplicating it in an expected URL.
for env_case in account account-url explicit-all; do
  case "$env_case" in
  account) write_env R2_ACCOUNT_ID=test-account ;;
  account-url) write_env R2_ACCOUNT_ID=test-account R2_S3_ENDPOINT_URL=https://jurisdiction.example ;;
  explicit-all) write_env R2_ACCOUNT_ID=test-account R2_S3_ENDPOINT=explicit.example R2_S3_ENDPOINT_URL=https://jurisdiction.example AWS_ENDPOINT_URL=https://other.example ;;
  esac
  for subpath in absent null '""' '"folder /%?#"'; do
    if [[ $subpath == absent ]]; then
      write_manifest '{}'
    else
      write_manifest "{\"destSubpath\":$subpath}"
    fi
    run_subject 0 photos
    cp "$test_root/calls" "$test_root/repair-calls"
    : >"$test_root/calls"
    env -i PATH="$PATH" HOME="$test_root/home" TMPDIR="$test_root/tmp" \
      TEST_CALLS="$test_root/calls" DUPLICATI_R2_TEST_CLI="$test_root/bin/duplicati-cli" \
      DUPLICATI_R2_CONFIG="$test_root/config.json" DUPLICATI_R2_TARGET=photos \
      bash "$test_root/backup.sh" >"$test_root/stdout" 2>"$test_root/stderr" || {
      cat "$test_root/stdout" "$test_root/stderr" >&2
      fail 'producer fixture failed'
    }
    jq -se --slurpfile repair "$test_root/repair-calls" '
      length == 1 and .[0][0] == "backup"
      and .[0][1] == $repair[0][1]
      and ([.[0][] | select(startswith("--dbpath="))] == [$repair[0][2]])
    ' "$test_root/calls" >/dev/null || fail "producer destination/database parity: $env_case $subpath"
  done
done
printf 'PASS generated backup producer destination/database parity\n'

# The wrapper always constructs S3 URLs. The adapter below substitutes only the
# destination so the actual captured maintenance argv can run on a local archive.
mkdir -p "$test_root/remote"
env -i PATH="$PATH" HOME="$test_root/home" TMPDIR="$test_root/tmp" \
  "$real_cli" backup "file://$test_root/remote" "$test_root/source" \
  "--dbpath=$test_root/state/duplicati-r2-photos.sqlite" --no-encryption=true \
  --disable-module=console-password-input --console-log-level=Warning >"$test_root/real-backup.log" 2>&1 || {
  cat "$test_root/real-backup.log" >&2
  fail 'real CLI synthetic backup failed'
}
write_env R2_ACCOUNT_ID=test-account
write_manifest '{"extraArgs":["--exclude=*.tmp","--INCLUDE=*.txt","--no-encryption=true","--disable-module=console-password-input"]}'
run_subject 0 --purge-broken-files photos -- --dry-run
mapfile -t calls <"$test_root/calls"
for call in "${calls[@]}"; do
  jq -j '.[] | ., "\u0000"' <<<"$call" >"$test_root/decoded-args"
  mapfile -d '' -t args <"$test_root/decoded-args"
  args[1]="file://$test_root/remote"
  env -i PATH="$PATH" HOME="$test_root/home" TMPDIR="$test_root/tmp" \
    "$real_cli" "${args[@]}" >"$test_root/real-maintenance.log" 2>&1 || {
    cat "$test_root/real-maintenance.log" >&2
    fail "real CLI ${args[0]} rejected wrapper arguments"
  }
  status=0
  env -i PATH="$PATH" HOME="$test_root/home" TMPDIR="$test_root/tmp" \
    "$real_cli" "${args[@]}" '--exclude=*.tmp' >"$test_root/filter-control.log" 2>&1 || status=$?
  [[ $status == 100 ]] || fail "filter positive control returned $status"
  grep -Fq 'Filters are not supported for this operation' "$test_root/filter-control.log"
done
printf 'PASS actual Duplicati local list/purge and filter rejection controls\n'
