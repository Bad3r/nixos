/*
  Package: exiftool
  Description: Comprehensive command-line utility for reading, writing, and editing metadata in media files.
  Homepage: https://exiftool.org/
  Documentation: https://exiftool.org/exiftool_pod.html
  Repository: https://github.com/exiftool/exiftool

  Summary:
    * Supports hundreds of metadata formats (EXIF, IPTC, XMP, GPS, Maker Notes) across images, audio, video, and document files.
    * Enables batch metadata extraction, conversion, and modification with rich filtering and output formatting options.

  Options:
    -r: Recursively process files in subdirectories.
    -json: Emit metadata as JSON for easier parsing.
    -P: Preserve original file timestamps when writing metadata.
    -overwrite_original: Modify files in place without creating backup copies.
    -TagsFromFile <src>: Copy tags from another file or directory, optionally filtered by tag list.

  Example Usage:
    * `exiftool photo.jpg` — Print all available tags for a single image.
    * `exiftool -r -json ~/Pictures | jq '.[].DateTimeOriginal'` — Recursively extract capture timestamps into JSON.
    * `exiftool -overwrite_original -All= image.jpg` — Strip all metadata from an image in place.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
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
          description = lib.mdDoc "Whether to enable exiftool.";
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
