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
*/
_:
let
  HashcatModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hashcat.extended;
    in
    {
      options.programs.hashcat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hashcat.";
        };

        package = lib.mkPackageOption pkgs "hashcat" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.hashcat = HashcatModule;
}
