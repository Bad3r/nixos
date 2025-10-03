/*
  Package: hashcat
  Description: Advanced password recovery utility supporting GPU acceleration.
  Homepage: https://hashcat.net/hashcat/
  Documentation: https://hashcat.net/wiki/
  Repository: https://github.com/hashcat/hashcat

  Summary:
    * Performs hybrid mask, dictionary, rule-based, and combinator attacks across numerous hash formats.
    * Supports OpenCL-enabled GPUs and distributes workloads via restore checkpoints.

  Options:
    hashcat -m <hash-type> -a 0 <hashes> <wordlist>: Run a dictionary attack for a specific hash type.
    hashcat --benchmark: Benchmark supported algorithms on available devices.
    hashcat --restore: Resume an interrupted cracking session.

  Example Usage:
    * `hashcat -m 0 -a 0 hashes.txt rockyou.txt` — Attempt MD5 hashes using a wordlist.
    * `hashcat -m 22000 handshake.hc22000 wordlist.txt -r rules/best64.rule` — Crack WPA2 handshakes with rule-based mangling.
    * `hashcat -I` — List detected compute devices before launching an attack.
*/

{
  flake.nixosModules.apps.hashcat =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hashcat ];
    };

}
