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
          pkgs.gnused
          pkgs.coreutils
        ];
        text = builtins.readFile ../../scripts/cache-coverage.sh;
      };
    };
}
