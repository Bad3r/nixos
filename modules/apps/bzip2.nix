/*
  Package: bzip2
  Description: High-quality block-sorting file compressor with libbz2 runtime utilities.
  Homepage: https://www.sourceware.org/bzip2
  Documentation: https://sourceware.org/git/?p=bzip2.git;a=blob_plain;f=manual/manual.html;hb=HEAD
  Repository: https://sourceware.org/git/?p=bzip2.git

  Summary:
    * Implements the Burrows–Wheeler transform based compressor producing `.bz2` archives and the libbz2 library.
    * Provides drop-in command-line tools (`bzip2`, `bunzip2`, `bzcat`) for integrating high-ratio compression into POSIX pipelines.

  Options:
    -k, --keep: Preserve input files during compression or decompression instead of removing them.
    -1 .. -9: Tune compression speed versus ratio; `-9` yields the smallest output, `-1` favors speed.
    -d, --decompress: Force decompression even when invoked via the `bzip2` executable.
    -t, --test: Verify the integrity of compressed data without writing output files.
    -c, --stdout: Write results to standard output for shell pipelines.

  Example Usage:
    * `bzip2 -9 backup.sql` — Compress a database dump with the strongest compression settings.
    * `bunzip2 -k logs.tar.bz2` — Decompress an archive while keeping the original compressed file.
    * `bzcat logs.tar.bz2 | tar xf -` — Stream a compressed tarball directly into `tar` without creating intermediate files.
*/

{
  flake.nixosModules.apps.bzip2 =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.bzip2 ];
    };

  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.bzip2 ];
    };
}
