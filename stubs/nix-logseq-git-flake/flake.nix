{
  description = "Stub logseq package for CI environments without the local mirror";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.logseq = pkgs.runCommand "logseq-unavailable" { } ''
                    mkdir -p "$out/share/doc"
                    cat <<'EOF' >"$out/share/doc/logseq-unavailable.txt"
          This is a stub build of nix-logseq-git-flake used for documentation extraction CI.
          No real Logseq binaries are provided.
          EOF
        '';
      }
    );
}
