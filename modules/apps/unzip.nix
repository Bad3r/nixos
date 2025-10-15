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

{
  flake.nixosModules.apps.unzip =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkAfter [ pkgs.unzip ];
    };

}
