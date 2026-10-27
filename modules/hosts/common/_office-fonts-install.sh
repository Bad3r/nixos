# shellcheck shell=bash
set -euo pipefail

: "${fontArchives[0]:?}" "${FONT_INSTALL_DIR:?}"
for archive in "${fontArchives[@]}"; do
  if [ ! -s "$archive" ]; then
    echo "Windows/Office font secret $archive is missing or empty" >&2
    exit 1
  fi
done

install -d -m 0755 "$(dirname "$FONT_INSTALL_DIR")"
backup="$FONT_INSTALL_DIR.old"
if [ -d "$backup" ] && [ ! -e "$FONT_INSTALL_DIR" ]; then
  mv -T "$backup" "$FONT_INSTALL_DIR"
fi

staging="$(mktemp -d "$FONT_INSTALL_DIR.new.XXXXXX")"
rotated=0
installed=0
committed=0
cleanup() {
  result=$?
  trap - EXIT
  rm -rf "$staging"
  if [ "$committed" -eq 0 ]; then
    if [ "$installed" -eq 1 ]; then
      rm -rf "$FONT_INSTALL_DIR"
    fi
    if [ "$rotated" -eq 1 ]; then
      mv -T "$backup" "$FONT_INSTALL_DIR"
      if ! fc-cache -f "$FONT_INSTALL_DIR/fonts"; then
        echo "Failed to refresh the restored Windows/Office font cache" >&2
        result=1
      fi
    fi
  fi
  exit "$result"
}
trap cleanup EXIT

cat "${fontArchives[@]}" |
  tar --no-same-owner --no-same-permissions -I zstd -xf - -C "$staging"
(
  cd "$staging"
  sha256sum --check --strict SHA256SUMS
)
if [ -z "$(find "$staging/fonts" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -print -quit)" ]; then
  echo "Windows/Office archive contains no font files" >&2
  exit 1
fi
families="$(find "$staging/fonts" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -exec fc-query -f '%{family}\n' {} +)"
for wanted in Aptos 'Aptos Slab' 'Georgia Pro' 'Verdana Pro'; do
  if [[ $families != *"$wanted"* ]]; then
    echo "Windows/Office archive has no face declaring $wanted" >&2
    exit 1
  fi
done
find "$staging" -type d -exec chmod 0755 {} +
find "$staging" -type f -exec chmod 0644 {} +

rm -rf "$backup"
if [ -d "$FONT_INSTALL_DIR" ]; then
  mv -T "$FONT_INSTALL_DIR" "$backup"
  rotated=1
fi
mv -T "$staging" "$FONT_INSTALL_DIR"
installed=1
fc-cache -f "$FONT_INSTALL_DIR/fonts"
committed=1
rm -rf "$backup"
