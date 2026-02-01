/*
  Package: czkawka-cli
  Description: Fast duplicate and unnecessary file finder with CLI interface.
  Homepage: https://github.com/qarmin/czkawka
  Documentation: https://github.com/qarmin/czkawka/blob/master/instructions/CLI.md
  Repository: https://github.com/qarmin/czkawka

  Summary:
    * Finds duplicates, empty files/folders, big files, temp files, similar images/videos, broken files, and invalid symlinks/extensions.
    * Supports BLAKE3, XXH3, and CRC32 hash algorithms for duplicate detection.

  Options:
    dup: Find duplicate files using hash, size, or name comparison.
    empty-folders: Find empty directories.
    big: Find files exceeding a size threshold.
    empty-files: Find zero-byte files.
    temp: Find temporary files matching common patterns.
    image: Find visually similar images.
    music: Find duplicate music by metadata tags.
    symlinks: Find broken symbolic links.
    broken: Find corrupted/broken files.
    video: Find similar video files.
    ext: Find files with mismatched extensions.
    -d: Directories to search (required, recursive by default).
    -e: Directories to exclude from search.
    -R: Disable recursive directory traversal.
    -t: Hash type selection (BLAKE3, CRC32, XXH3); defaults to BLAKE3.
    -m: Minimum file size in bytes; defaults to 8192 (8KB).
    -D: Deletion method (AEO=all except oldest, AEN=all except newest, NONE=report only).
    --dry-run: Preview deletions without modifying files.

  Notes:
    * Part of the czkawka package which includes both CLI and GUI binaries.
    * Polish word "czkawka" means "hiccup".
*/
_:
let
  CzkawkaCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.czkawka-cli.extended;
    in
    {
      options.programs.czkawka-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable czkawka-cli.";
        };

        package = lib.mkPackageOption pkgs "czkawka" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.czkawka-cli = CzkawkaCliModule;
}
