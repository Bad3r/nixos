# The dev-shell wrapper as a package, so its runtimeInputs are a build artifact
# the checks can exercise rather than something only `nix develop` assembles.
_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.prune-old-stashes = pkgs.writeShellApplication {
        name = "prune-old-stashes";
        runtimeInputs = with pkgs; [
          git
          coreutils
          util-linux
        ];
        text = builtins.readFile ../../scripts/prune-old-stashes.sh;
      };
    };
}
