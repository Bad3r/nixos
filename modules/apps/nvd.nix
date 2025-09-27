/*
  Package: nvd
  Description: Nix package diff tool for comparing derivation closures.
  Homepage: https://github.com/vlinkz/nvd
  Documentation: https://github.com/vlinkz/nvd#readme
  Repository: https://github.com/vlinkz/nvd

  Summary:
    * Compares two Nix store closures to show added, removed, or upgraded packages between generations.
    * Supports JSON summaries for integration into CI pipelines and release notes.

  Options:
    --json: Produce machine-readable diff output for integration with CI pipelines.
    --wide: Expand the diff view to include derivation attribute paths.
    --exit-status: Return non-zero exit codes when differences are detected.
*/

/*
  Package: nvd
  Description: Nix package diff tool for comparing derivation closures.
  Homepage: https://github.com/vlinkz/nvd
  Documentation: https://github.com/vlinkz/nvd#readme
  Repository: https://github.com/vlinkz/nvd

  Summary:
    * Compares two Nix store closures to show added, removed, or upgraded packages between generations.
    * Supports JSON summaries for integration into CI pipelines and release notes.

  Options:
    nvd diff <path> <path>: Compare two closure directories or switching profiles.
    nvd --json diff <path> <path>: Produce machine-readable diff output.
    nvd -s diff <path> <path>: Summarize changes grouped by derivation.
*/

{
  flake.nixosModules.apps.nvd =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nvd ];
    };
}
