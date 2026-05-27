# Local repository mirrors (shared hosts).
# GitHub shorthand syncs daily to /data/git/{owner}-{repo}; full URLs use
# a normalized host-prefixed path.
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
        firefoxDocs.enable = true;
        jobs = 2;
        repos = [
          # NixOS
          "NixOS/nix"
          "NixOS/nixos-hardware"
          "NixOS/nixpkgs"
          "NixOS/rfcs"

          # Lix
          "https://git.lix.systems/lix-project/lix.git"
          "https://git.lix.systems/lix-project/lix-installer.git"
          "https://git.lix.systems/lix-project/nixos-module.git"

          # Determinate Nix (DeterminateSystems)
          "DeterminateSystems/nix-installer"

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
          "mozilla-firefox/firefox"
          "mdn/content" # https://developer.mozilla.org
          "mozilla/policy-templates"
          "mozilla/enterprise-admin-reference" # Documentation for policy behavior and syntax

          # Applications
          "https://codeberg.org/librewolf/settings.git"
          "better-auth/better-auth"
          "cloudflare/workers-sdk"
          "duplicati/duplicati"
          "logseq/logseq"
          "openai/codex"
          "rclone/rclone"
          "restic/restic"
          "s0md3v/wappalyzer-next"
          "tridactyl/tridactyl"

          # Zap (Zed Attack Proxy)
          "zaproxy/zaproxy"
          "zaproxy/zap-extensions"
          "zaproxy/zap-api-python"
          "zaproxy/community-scripts"
          "fuzzdb-project/fuzzdb"
          "dtkmn/mcp-zap-server"

        ];
      };
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
