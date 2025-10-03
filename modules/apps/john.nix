/*
  Package: john
  Description: John the Ripper password cracking suite with jumbo community patches.
  Homepage: https://www.openwall.com/john/
  Documentation: https://www.openwall.com/john/doc/
  Repository: https://github.com/openwall/john

  Summary:
    * Supports extensive hash formats, hybrid attacks, and GPU acceleration via OpenCL.
    * Includes wordlist mangling, mask attacks, and session management for long-running jobs.

  Options:
    john --wordlist=<file> <hashes>: Run a straightforward wordlist attack.
    john --incremental <hashes>: Try incremental brute-force based on character sets.
    john --restore=<session>: Resume a paused cracking session.

  Example Usage:
    * `john --format=sha512crypt hashes.txt` — Crack Linux shadow hashes.
    * `john --wordlist=rockyou.txt --rules hashes.txt` — Apply mangling rules to a wordlist.
    * `john --show hashes.txt` — Display recovered credentials once cracking finishes.
*/

{
  flake.nixosModules.apps.john =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.john ];
    };

}
