/*
  Package: file
  Description: Utility that identifies file types using libmagic pattern matching.
  Homepage: https://darwinsys.com/file/
  Documentation: https://man.archlinux.org/man/file.1.en
  Repository: https://github.com/file/file

  Summary:
    * Detects file formats by inspecting magic numbers, MIME types, and encoding heuristics.
    * Supports custom magic databases to recognize organization-specific file signatures.

  Options:
    -i <path>: Print MIME type strings alongside file names.
    -L <path>: Follow symlinks before identifying the target file.
    -z <path>: Inspect compressed files by decompressing them in memory.
*/

{
  flake.nixosModules.apps.file =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.file ];
    };
}
