# Local repository mirrors for system76 host.
# Synced daily to /data/git/{owner}-{repo}
{ metaOwner, ... }:
{
  configurations.nixos.system76.module = _: {
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
          "nix-community/nixvim"
          "nix-community/stylix"

          # Flake inputs / tooling
          "numtide/llm-agents.nix"
          "Mic92/sops-nix"
          "cachix/git-hooks.nix"
          "hercules-ci/flake.parts-website"
          "mightyiam/files"
          "numtide/treefmt-nix"
          "vic/import-tree"

          # Documentation
          "github/docs"
          "i3/i3.github.io"

          # Applications
          "logseq/logseq"
        ];
      };
    };
  };
}
