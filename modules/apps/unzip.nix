/*
  Package: unzip
  Description: Info-ZIP command-line extractor for .zip archives across Unix-like systems.
  Homepage: http://www.info-zip.org
  Documentation: https://infozip.sourceforge.net/UnZip.html
  Repository: https://github.com/madler/unzip

  Summary:
    * Extracts, lists, and tests ZIP archives while preserving directory hierarchy and file attributes.
    * Handles encrypted entries, large Zip64 archives, and pattern-based include or exclude filters for selective extraction.

  Options:
    -l: List archive contents without extracting.
    -t: Test archive integrity by decompressing to memory.
    -d DIR: Extract files into the specified directory.
    -x PATTERN: Exclude files that match the given pattern during extraction.
    -o: Overwrite existing files without prompting.
*/
_:
let
  UnzipModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.unzip.extended;
    in
    {
      options.programs.unzip.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable unzip.";
        };

        package = lib.mkPackageOption pkgs "unzip" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.unzip = UnzipModule;
}
