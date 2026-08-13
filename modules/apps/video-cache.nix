/*
  Package: video-cache
  Description: Build and maintain a cache of video file durations for filtering and playback.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/tree/main/packages/video-cache

  Summary:
    * Scans directories for video files and caches their durations in TSV format.
    * Supports incremental updates: removes deleted files, adds new ones, skips cached.
    * Emits matching videos in depth-first tree order with natural numeric sorting.

  Options:
    --force: Clear cache and rescan all files.
    --quiet: Suppress progress bar and summary output.

  Notes:
    * Package defined in packages/video-cache/default.nix and exposed via overlay.
    * Cache stored at <video_dir>/.cache/video-durations.tsv.
    * Errors logged to <video_dir>/.cache/video-errors.log.
*/
_:
let
  VideoCacheModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.video-cache.extended;
    in
    {
      options.programs.video-cache.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable video-cache.";
        };

        package = lib.mkPackageOption pkgs "video-cache" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.video-cache = VideoCacheModule;

  perSystem =
    { pkgs, ... }:
    let
      # The locale assertion needs one archive entry, not the full locale set.
      checkLocales = pkgs.glibcLocales.override {
        allLocales = false;
        locales = [ "en_US.UTF-8/UTF-8" ];
      };
      # Fixture files are empty, so the real ffprobe reports no duration for any
      # of them and every path lands in the error log instead of the cache,
      # leaving nothing to order.
      ffprobeStub = pkgs.writeShellApplication {
        name = "ffprobe";
        text = ''
          echo 120.000000
        '';
      };
      # video-cache execs mpv, so the playlist exists only as an argument
      # vector. Everything after -- is the playlist, in order.
      mpvStub = pkgs.writeShellApplication {
        name = "mpv";
        text = ''
          seen=0
          for arg in "$@"; do
            if [ "$seen" = 0 ]; then
              if [ "$arg" = "--" ]; then
                seen=1
              fi
              continue
            fi
            printf '%s\n' "$arg"
          done
        '';
      };
      videoCache = pkgs.callPackage ../../packages/video-cache {
        ffmpeg = ffprobeStub;
        mpv = mpvStub;
      };
    in
    {
      # Opts this check into the "Run runtime check suites" step in
      # .github/workflows/check.yml, which is what executes it: the flake-check
      # step only forces drvPaths. passthru rather than a plain attr, since
      # runCommand's second argument is derivationArgs and a plain one would
      # join the derivation hash.
      #
      # Building this is also the only thing that reaches the package's
      # writeShellApplication shellcheck pass, since nothing else in CI builds
      # an overlay-only package.
      checks."apps/video-cache-tree-order" =
        pkgs.runCommand "video-cache-tree-order-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = with pkgs; [
              coreutils
              diffutils
              glibc.bin
              gnugrep
              gnused
            ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            export HOME="$PWD/home"
            mkdir -p "$HOME"

            subject=${videoCache}/bin/video-cache
            fixture="$PWD/fixture"
            mkdir -p "$fixture/Show A/extras" "$fixture/The Office" "$fixture/clips"

            run99=$(printf '%099d' 0)
            run99=''${run99//0/9}
            run100=$(printf '%0100d' 0)
            run100=''${run100//0/9}
            long99="Show A/ep''${run99}.mkv"
            long100="Show A/ep''${run100}.mkv"
            tab_name=$'Tab\tName.mp4'
            leading_tab_name=$'\tleading-tab.mp4'

            # Each name isolates one failure mode of a flat path sort: ep2/ep10
            # the numeric one, "Show A" against "Show A.mp4" the
            # directory-versus-sibling one, "The Office" against "the-100.mp4"
            # the case-and-punctuation one, the long runs the natural-number
            # length boundary, and both tab names the cache record round-trip.
            for f in \
              "Alpha.mp4" "Show A.mp4" "the-100.mp4" "zebra.mp4" \
              "Show A/ep2.mkv" "Show A/ep10.mkv" "Show A/extras/bloopers.mkv" \
              "The Office/s01e09.mkv" "The Office/s01e10.mkv" \
              "clips/a.mp4" "clips/b.mp4" "notes.txt" "$long99" "$long100" \
              "$tab_name" "$leading_tab_name"; do
              : >"$fixture/$f"
            done

            printf '%s\n' \
              "$leading_tab_name" \
              'Alpha.mp4' \
              'clips/a.mp4' \
              'clips/b.mp4' \
              'Show A/ep2.mkv' \
              'Show A/ep10.mkv' \
              "$long99" \
              "$long100" \
              'Show A/extras/bloopers.mkv' \
              'Show A.mp4' \
              "$tab_name" \
              'The Office/s01e09.mkv' \
              'The Office/s01e10.mkv' \
              'the-100.mp4' \
              'zebra.mp4' \
              >expected

            playlist() {
              "$subject" --path "$fixture" "$@" --quiet | sed "s|^$fixture/||"
            }

            # 1. Fresh scan: fd discovery order must not reach the playlist.
            playlist >actual-scan
            if ! diff -u expected actual-scan; then
              echo "fresh scan did not produce tree order" >&2
              exit 1
            fi

            # The ordering is pinned inside the package, not just by this
            # sandbox's unset locale environment.
            (
              export LOCALE_ARCHIVE=${checkLocales}/lib/locale/locale-archive
              export LC_ALL=en_US.UTF-8
              if [[ "$(locale charmap)" != UTF-8 ]]; then
                echo "en_US.UTF-8 locale is unavailable in the check environment" >&2
                exit 1
              fi
              playlist >actual-locale
            )
            if ! diff -u expected actual-locale; then
              echo "playlist order depends on the caller's locale" >&2
              exit 1
            fi

            # 2. An existing cache in arbitrary order must be rewritten, and the
            #    duration filter must not reorder what survives it. Every path
            #    is already cached, so this run reaches no ffprobe.
            cache="$fixture/.cache/video-durations.tsv"
            printf '600\t%s\n' \
              "$fixture/zebra.mp4" \
              "$fixture/Show A/ep10.mkv" \
              "$fixture/$long99" \
              "$fixture/$long100" \
              "$fixture/Alpha.mp4" \
              "$fixture/Show A.mp4" \
              "$fixture/Show A/ep2.mkv" \
              "$fixture/The Office/s01e10.mkv" \
              "$fixture/clips/b.mp4" \
              "$fixture/The Office/s01e09.mkv" \
              "$fixture/Show A/extras/bloopers.mkv" \
              "$fixture/clips/a.mp4" \
              "$fixture/$tab_name" \
              "$fixture/$leading_tab_name" \
              "$fixture/the-100.mp4" \
              >"$cache"

            cache_mode=$(stat -c '%a' "$cache")
            foreign_tmp="$PWD/foreign-tmp"
            mkdir -p "$foreign_tmp"
            TMPDIR="$foreign_tmp" playlist -d 600 >actual-seeded
            if ! diff -u expected actual-seeded; then
              echo "a pre-existing cache was not rewritten into tree order" >&2
              exit 1
            fi
            if [[ "$(stat -c '%a' "$cache")" != "$cache_mode" ]]; then
              echo "cache mode changed during replacement" >&2
              exit 1
            fi
            tab_cache_line=$(printf '600\t%s' "$fixture/$tab_name")
            if ! grep -Fqx -- "$tab_cache_line" "$cache"; then
              echo "tab-containing cache record was not preserved" >&2
              exit 1
            fi
            leading_tab_cache_line=$(printf '600\t%s' "$fixture/$leading_tab_name")
            if ! grep -Fqx -- "$leading_tab_cache_line" "$cache"; then
              echo "leading-tab cache record was not preserved" >&2
              exit 1
            fi
            for temp_file in "$fixture"/.cache/.video-durations.*; do
              if [[ -e "$temp_file" ]]; then
                echo "cache replacement leaked a temporary file" >&2
                exit 1
              fi
            done
            for temp_file in "$foreign_tmp"/.video-durations.*; do
              if [[ -e "$temp_file" ]]; then
                echo "cache replacement ignored its cache-directory template" >&2
                exit 1
              fi
            done

            # 3. The rewrite is a fixpoint: a second pass must not move a line
            # or make the tab-containing file look new again.
            cp "$cache" pass1.tsv
            playlist >/dev/null
            if ! diff -u pass1.tsv "$cache"; then
              echo "the cache sort is not idempotent" >&2
              exit 1
            fi

            # 3b. Exercise both cache-pruning rejection paths. The malformed
            # record names an existing file so removing the no-tab guard cannot
            # be masked by the missing-file branch.
            rm -- "$fixture/clips/b.mp4"
            malformed_path="$fixture/malformed-no-tab"
            : >"$malformed_path"
            printf '%s\n' "$malformed_path" >>"$cache"
            playlist >/dev/null
            if grep -Fq -- "$fixture/clips/b.mp4" "$cache"; then
              echo "a deleted file was not pruned from the cache" >&2
              exit 1
            fi
            if grep -Fqx -- "$malformed_path" "$cache"; then
              echo "a record without a tab delimiter was not rejected" >&2
              exit 1
            fi
            if ! grep -Fqx -- "$leading_tab_cache_line" "$cache"; then
              echo "pruning dropped or reprobed an unrelated record" >&2
              exit 1
            fi

            # 4. A failed cache read must leave the original record and remove
            # the replacement file created before the failure.
            failure_fixture="$PWD/failure-fixture"
            mkdir -p "$failure_fixture/.cache"
            : >"$failure_fixture/failed.mp4"
            failure_cache="$failure_fixture/.cache/video-durations.tsv"
            printf '600\t%s\n' "$failure_fixture/failed.mp4" >"$failure_cache"
            cp "$failure_cache" failure-cache.before
            chmod 000 "$failure_cache"
            if "$subject" --path "$failure_fixture" --quiet >failure.out 2>failure.err; then
              echo "an unreadable cache unexpectedly succeeded" >&2
              exit 1
            fi
            chmod 600 "$failure_cache"
            if ! cmp -s failure-cache.before "$failure_cache"; then
              echo "a failed cache update changed the original record" >&2
              exit 1
            fi
            for temp_file in "$failure_fixture"/.cache/.video-durations.*; do
              if [[ -e "$temp_file" ]]; then
                echo "failed cache update leaked a temporary file" >&2
                exit 1
              fi
            done

            touch "$out"
          '';
    };
}
