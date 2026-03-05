# Local repository mirrors for tpnix host.
# Synced daily to /data/git/{owner}-{repo}
{ lib, metaOwner, ... }:
{
  configurations.nixos.tpnix.module = _: {
    config = {
      localMirrors.enable = lib.mkDefault false;

      home-manager.users.${metaOwner.username}.programs.gitMirror = {
        enable = lib.mkDefault false;
        repos = [
          # NixOS
          "NixOS/nixos-hardware"
          "NixOS/nixpkgs"

          # Nix community
          "nix-community/home-manager"
          "nix-community/nh"
          "nix-community/nixvim"
          "nix-community/stylix"

          # Flake inputs / tooling
          "numtide/llm-agents.nix"
          "Mic92/sops-nix"
          "cachix/git-hooks.nix"
          "cachix/docs.cachix.org"
          "evilmartians/lefthook"
          "hercules-ci/flake.parts-website"
          "mightyiam/files"
          "numtide/treefmt-nix"
          "vic/import-tree"

          # Documentation
          "github/docs"
          "i3/i3.github.io"

          # Applications
          "better-auth/better-auth"
          "logseq/logseq"
          "openai/codex"
          "s0md3v/wappalyzer-next"
        ];
      };
    };
  };
}
