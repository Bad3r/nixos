#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FONT_INSTALLER="$SCRIPT_DIR/../../modules/hosts/common/_office-fonts-install.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home"
export SOPS_AGE_KEY_FILE="$work/identity.txt"
export FONT_INSTALL_DIR="$work/install/windows-office"
export TEST_FAMILIES="$work/families"
mkdir -p "$HOME" "$work/bin" "$work/payload/fonts"
age-keygen -o "$SOPS_AGE_KEY_FILE" >"$work/keygen.log" 2>&1
recipient="$(age-keygen -y "$SOPS_AGE_KEY_FILE")"
printf 'creation_rules:\n  - age: %s\n' "$recipient" >"$work/.sops.yaml"

printf '#!%s\n' "$BASH" >"$work/bin/fc-query"
cat >>"$work/bin/fc-query" <<'EOF'
cat "$TEST_FAMILIES"
EOF
printf '#!%s\n' "$BASH" >"$work/bin/fc-cache"
cat >>"$work/bin/fc-cache" <<'EOF'
if [[ ${FAIL_CACHE:-0} == 1 ]]; then
  exit 42
fi
EOF
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
printf '%s\n' Aptos 'Aptos Slab' 'Georgia Pro' 'Verdana Pro' >"$TEST_FAMILIES"
printf 'transaction test payload\n' >"$work/payload/fonts/test.ttf"
(
  cd "$work/payload"
  sha256sum fonts/test.ttf >SHA256SUMS
)
tar -I zstd -cf "$work/fonts.tar.zst" -C "$work/payload" .
split -n 2 -d "$work/fonts.tar.zst" "$work/part-"
encrypt() {
  sops --config "$work/.sops.yaml" encrypt --input-type binary --output-type binary --output "$2" "$1"
}
for part in 00 01; do
  encrypt "$work/part-$part" "$work/part-$part.enc"
done

run_installer() {
  status=0
  bash -c 'fontArchives=("$@"); source "$FONT_INSTALLER"' _ "$@" >"$work/run.log" 2>&1 || status=$?
}

fail() {
  echo "FAIL: $1" >&2
  cat "$work/run.log" >&2
  exit 1
}

run_installer "$work/part-00.enc" "$work/part-01.enc"
[[ $status == 0 ]] || fail 'initial streaming installation'
cmp "$work/payload/fonts/test.ttf" "$FONT_INSTALL_DIR/fonts/test.ttf"
[[ $(stat -c %a "$FONT_INSTALL_DIR/fonts/test.ttf") == 644 ]] || fail 'font permissions'

mkdir -p "$FONT_INSTALL_DIR.new" "$FONT_INSTALL_DIR.new.stale"
printf orphan >"$FONT_INSTALL_DIR.new/stale"
printf orphan >"$FONT_INSTALL_DIR.new.stale/stale"
run_installer "$work/part-00.enc" "$work/part-01.enc"
[[ $status == 0 ]] || fail 'repeat installation'
[[ ! -e $FONT_INSTALL_DIR.new && ! -e $FONT_INSTALL_DIR.new.stale ]] || fail 'stale staging cleanup'

printf previous >"$FONT_INSTALL_DIR/marker"
printf '%s\n' 'Aptos Slab' 'Georgia Pro' 'Verdana Pro' >"$TEST_FAMILIES"
run_installer "$work/part-00.enc" "$work/part-01.enc"
[[ $status != 0 && -e $FONT_INSTALL_DIR/marker ]] || fail 'Aptos Slab must not satisfy Aptos'
printf '%s\n' Aptos 'Aptos Slab' 'Georgia Pro' 'Verdana Pro' >"$TEST_FAMILIES"

export FAIL_CACHE=1
run_installer "$work/part-00.enc" "$work/part-01.enc"
[[ $status != 0 && -e $FONT_INSTALL_DIR/marker ]] || fail 'cache failure rollback'
unset FAIL_CACHE

printf 'not a SOPS document\n' >"$work/broken.enc"
encrypt "$work/fonts.tar.zst" "$work/complete.enc"
run_installer "$work/broken.enc" "$work/complete.enc"
[[ $status != 0 && -e $FONT_INSTALL_DIR/marker ]] || fail 'failed first decryption cannot be ignored'

printf 'corrupted\n' >"$work/payload/fonts/test.ttf"
tar -I zstd -cf "$work/corrupt.tar.zst" -C "$work/payload" .
encrypt "$work/corrupt.tar.zst" "$work/corrupt.enc"
run_installer "$work/corrupt.enc"
[[ $status != 0 && -e $FONT_INSTALL_DIR/marker ]] || fail 'checksum failure must preserve installation'

mv "$FONT_INSTALL_DIR" "$FONT_INSTALL_DIR.old"
run_installer "$work/broken.enc"
[[ $status != 0 && -e $FONT_INSTALL_DIR/marker ]] || fail 'interrupted swap recovery'
[[ ! -e $FONT_INSTALL_DIR.old && ! -e $FONT_INSTALL_DIR.new ]] || fail 'recovery cleanup'
echo 'PASS: streaming, repeat install, staging cleanup, exact families, rollback, decrypt/checksum failures, and recovery'
