{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      config.lib.stylix.colors.withHashtag = {
        base00 = "#0d1117";
        base05 = "#e6edf3";
        base06 = "#f0f6fc";
        base0D = "#4493f8";
      };
      gecko = import ./_gecko-mk-profile.nix {
        inherit pkgs lib config;
        osConfig = { };
      };
      inherit (import ./_gecko-extensions.nix { inherit pkgs lib config; })
        darkreaderPalette
        darkreaderStorageSeed
        ;
    in
    {
      checks."browsers/darkreader-palette-refresh" =
        pkgs.runCommand "darkreader-palette-refresh-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = [
              pkgs.diffutils
              pkgs.jq
            ];
          }
          ''
            set -o errexit -o nounset -o pipefail
            refresh=${lib.getExe gecko.darkreaderPaletteRefresh}
            palette=${darkreaderPalette}
            root="$TMPDIR/profiles"
            state="$TMPDIR/state"
            storage() { echo "$root/$1/browser-extension-data/addon@darkreader.org/storage.js"; }
            fail() { echo "darkreader-palette-refresh: $*" >&2; exit 1; }
            expect() {
              got="$(jq -r "$2" "$(storage "$1")")"
              [ "$got" = "$3" ] || fail "$1 $2 is $got, expected $3"
            }

            echo '{"darkSchemeBackgroundColor":"#010101","darkSchemeTextColor":"#020202","lightSchemeBackgroundColor":"#030303","lightSchemeTextColor":"#040404","scrollbarColor":"#050505","selectionColor":"#060606"}' > old.json
            for profile in changed unrecorded; do
              mkdir -p "$(dirname "$(storage "$profile")")"
            done
            # On the old palette, with an edited global background and a runtime
            # site theme left on the palette.
            jq -c --slurpfile old old.json '
              .theme += $old[0]
              | .customThemes += [{url: ["example.org"], theme: .theme}]
              | .theme.darkSchemeBackgroundColor = "#123456"
            ' ${darkreaderStorageSeed} > "$(storage changed)"
            mkdir "$state"
            cp old.json "$state/changed.json"
            # No palette record, one edited color, one color missing.
            jq -c '.theme.darkSchemeBackgroundColor = "#123456" | del(.theme.selectionColor)' \
              ${darkreaderStorageSeed} > "$(storage unrecorded)"
            mkdir before
            cp -a "$root" "$state" before/

            DARKREADER_DRY_RUN=1 "$refresh" "$root" "$state" > dry.out
            grep -q "would refresh palette colors in $(storage changed)" dry.out || fail "dry run reported no pending refresh"
            diff -r before/profiles "$root" || fail "dry run wrote storage.js"
            diff -r before/state "$state" || fail "dry run wrote palette state"

            "$refresh" "$root" "$state"
            expect changed '.theme.darkSchemeBackgroundColor' "#123456"
            expect changed '.theme.darkSchemeTextColor' "$(jq -r .darkSchemeTextColor "$palette")"
            expect changed '.customThemes[-1].theme.darkSchemeBackgroundColor' "$(jq -r .darkSchemeBackgroundColor "$palette")"
            [ "$(jq -c '.customThemes[:-1]' "$(storage changed)")" = "$(jq -c .customThemes ${darkreaderStorageSeed})" ] ||
              fail "cssFilter site themes changed"
            expect unrecorded '.theme.darkSchemeBackgroundColor' "#123456"
            expect unrecorded '.theme.selectionColor' "$(jq -r .selectionColor "$palette")"
            for profile in changed unrecorded; do
              cmp "$palette" "$state/$profile.json" || fail "$profile palette state is not the current palette"
            done

            cp -a "$root" after
            "$refresh" "$root" "$state" > second.out 2>&1
            [ ! -s second.out ] || fail "second run printed: $(cat second.out)"
            diff -r after "$root" || fail "second run rewrote storage.js"

            touch "$out"
          '';
    };
}
