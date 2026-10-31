/*
  Package: exiftool
  Description: Comprehensive command-line utility for reading, writing, and editing metadata in media files.
  Homepage: https://exiftool.org/
  Documentation: https://exiftool.org/exiftool_pod.html
  Repository: https://github.com/exiftool/exiftool

  Summary:
    * Reads and writes EXIF, IPTC, XMP, GPS, and maker-note metadata across image, audio, video, and document files.
    * Extracts, converts, and edits metadata in batches with filtering and formatted output.

  Options:
    -r: Recursively process files in subdirectories.
    -json: Emit metadata as JSON for easier parsing.
    -P: Preserve original file timestamps when writing metadata.
    -overwrite_original: Modify files in place without creating backup copies.
    -TagsFromFile <src>: Copy tags from another file or directory, optionally filtered by tag list.
*/
_:
let
  ExiftoolModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.exiftool.extended;
    in
    {
      options.programs.exiftool.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable exiftool.";
        };

        package = lib.mkPackageOption pkgs "exiftool" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.exiftool = ExiftoolModule;
}
