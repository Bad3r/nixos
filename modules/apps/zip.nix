/*
  Package: zip
  Description: Info-ZIP command-line archiver for creating and updating .zip files.
  Homepage: http://www.info-zip.org
  Documentation: https://infozip.sourceforge.net/Zip.html
  Repository: https://sourceforge.net/projects/infozip/

  Summary:
    * Creates new archives or appends, updates, and deletes members inside existing .zip files with DOS, Unix, and VMS attribute support.
    * Supports recursive directory compression, pattern-based inclusion/exclusion, and optional password protection compatible with PKZIP.

  Options:
    -r: Recursively add directories and their contents to the archive.
    -x PATTERN: Exclude files that match the shell-style pattern from being stored.
    -j: Store files without directory paths ("junk" the paths) inside the archive.
    -9: Use maximum compression; smaller values (for example `-1`) trade ratio for speed.
    -e: Encrypt entries using legacy ZipCrypto password prompts compatible with PKZIP 2.x.

  Example Usage:
    * `zip -r site-backup.zip public/` — Archive a project directory recursively.
    * `zip -r build.zip dist/ -x "*.map"` — Exclude source maps while packaging a build output.
    * `zip -e secrets.zip notes.txt` — Protect sensitive files with a password prompt compatible with PKZIP.
*/

{
  flake.nixosModules.apps.zip =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.zip ];
    };

}
