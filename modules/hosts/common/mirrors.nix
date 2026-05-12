# Local repository mirrors (shared hosts).
# Synced daily to /data/git/{owner}-{repo}
{
  metaOwner,
  ...
}:
let
  body = _: {
    config = {
      localMirrors.enable = true;

      home-manager.users.${metaOwner.username}.programs.gitMirror = {
        enable = true;
        repos = [
          # NixOS
          "NixOS/nixos-hardware"
          "NixOS/nixpkgs"

          # Nix community
          "nix-community/home-manager"
          "nix-community/nh"
          "nix-community/nixd"
          "nix-community/nixvim"
          "nix-community/stylix"

          # Flake inputs / tooling
          "numtide/llm-agents.nix"
          "Mic92/sops-nix"
          "cachix/devenv"
          "cachix/git-hooks.nix"
          "cachix/docs.cachix.org"
          "evilmartians/lefthook"
          "hercules-ci/flake-parts"
          "hercules-ci/flake.parts-website"
          "mightyiam/files"
          "numtide/treefmt"
          "numtide/treefmt-nix"
          "vic/import-tree"

          # Documentation
          "duplicati/documentation"
          "github/docs"
          "i3/i3.github.io"

          # Applications
          "better-auth/better-auth"
          "cloudflare/workers-sdk"
          "duplicati/duplicati"
          "logseq/logseq"
          "openai/codex"
          "rclone/rclone"
          "restic/restic"
          "s0md3v/wappalyzer-next"
        ];
      };
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
