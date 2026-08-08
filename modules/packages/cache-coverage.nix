_: {
  perSystem =
    { pkgs, ... }:
    {
      # Wrapper for scripts/cache-coverage.sh: `nix run .#cache-coverage`
      # (path:. in linked worktrees). The script stays the source of truth
      # so it also runs standalone; writeShellApplication shellchecks the
      # composed text at build time.
      packages.cache-coverage = pkgs.writeShellApplication {
        name = "cache-coverage";
        runtimeInputs = [
          pkgs.lixPackageSets.latest.lix
          pkgs.curl
          pkgs.jq
          pkgs.gitMinimal
          pkgs.gawk
          # The prepended guard is the only user of grep, which decides whether
          # the scan applies at all. writeShellApplication only prepends
          # runtimeInputs, so without it that resolves from whatever PATH the
          # caller happens to have.
          pkgs.gnugrep
          pkgs.coreutils
        ];
        # The secrets guard is prepended rather than left to the script's
        # source line: nothing sits beside the script here, and this route
        # reaches the same unfiltered path: ref the guard exists to catch
        # whenever the script resolves one. It cannot cover the installable the
        # operator typed: `nix run path:.#cache-coverage` has Lix copy the tree
        # to build this wrapper, before its first statement.
        # The script skips its own source when the functions are already
        # defined, so the checkout and the wrapper run identical logic.
        text =
          builtins.readFile ../../scripts/lib/secrets-guard.sh
          + "\n"
          + builtins.readFile ../../scripts/cache-coverage.sh;
      };
    };
}
