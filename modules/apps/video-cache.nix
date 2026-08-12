/*
  Package: video-cache
  Description: Build and maintain a cache of video file durations for filtering and playback.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/tree/main/packages/video-cache

  Summary:
    * Scans directories for video files and caches their durations in TSV format.
    * Supports incremental updates: removes deleted files, adds new ones, skips cached.

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

            # Each name isolates one failure mode of a flat path sort: ep2/ep10
            # the numeric one, "Show A" against "Show A.mp4" the
            # directory-versus-sibling one, "The Office" against "the-100.mp4"
            # the case-and-punctuation one, notes.txt the extension filter.
            for f in \
              "Alpha.mp4" "Show A.mp4" "the-100.mp4" "zebra.mp4" \
              "Show A/ep2.mkv" "Show A/ep10.mkv" "Show A/extras/bloopers.mkv" \
              "The Office/s01e09.mkv" "The Office/s01e10.mkv" \
              "clips/a.mp4" "clips/b.mp4" "notes.txt"; do
              : >"$fixture/$f"
            done

            printf '%s\n' \
              'Alpha.mp4' \
              'clips/a.mp4' \
              'clips/b.mp4' \
              'Show A/ep2.mkv' \
              'Show A/ep10.mkv' \
              'Show A/extras/bloopers.mkv' \
              'Show A.mp4' \
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

            # 2. An existing cache in arbitrary order must be rewritten, and the
            #    duration filter must not reorder what survives it. Every path
            #    is already cached, so this run reaches no ffprobe.
            cache="$fixture/.cache/video-durations.tsv"
            printf '600\t%s\n' \
              "$fixture/zebra.mp4" \
              "$fixture/Show A/ep10.mkv" \
              "$fixture/Alpha.mp4" \
              "$fixture/Show A.mp4" \
              "$fixture/Show A/ep2.mkv" \
              "$fixture/The Office/s01e10.mkv" \
              "$fixture/clips/b.mp4" \
              "$fixture/The Office/s01e09.mkv" \
              "$fixture/Show A/extras/bloopers.mkv" \
              "$fixture/clips/a.mp4" \
              "$fixture/the-100.mp4" \
              >"$cache"

            playlist -d 600 >actual-seeded
            if ! diff -u expected actual-seeded; then
              echo "a pre-existing cache was not rewritten into tree order" >&2
              exit 1
            fi

            # 3. The rewrite is a fixpoint: a second pass must not move a line.
            cp "$cache" pass1.tsv
            playlist >/dev/null
            if ! diff -u pass1.tsv "$cache"; then
              echo "the cache sort is not idempotent" >&2
              exit 1
            fi

            touch "$out"
          '';
    };
}
