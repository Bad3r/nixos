/*
  Package: b3sum
  Description: BLAKE3 cryptographic hash function.
  Homepage: https://github.com/BLAKE3-team/BLAKE3/
  Documentation: https://github.com/BLAKE3-team/BLAKE3/tree/master/b3sum
  Repository: https://github.com/BLAKE3-team/BLAKE3

  Summary:
    * Computes BLAKE3 hashes for files with coreutils-style checksum output.
    * Verifies checksum manifests and supports keyed hashing or key derivation modes.

  Options:
    --check: Read BLAKE3 sums from input files and verify the referenced paths.
    --derive-key <CONTEXT>: Derive keyed output using the provided context string.
    --keyed: Compute keyed hashes using a 32-byte key from standard input.
    --no-names: Omit filenames from output when hashing input streams or single files.
    --raw: Write raw digest bytes instead of hexadecimal text output.
    --tag: Emit BSD-style checksum output instead of the default GNU format.
*/
_:
let
  B3sumModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.b3sum.extended;
    in
    {
      options.programs.b3sum.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable b3sum.";
        };

        package = lib.mkPackageOption pkgs "b3sum" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.b3sum = B3sumModule;
}
