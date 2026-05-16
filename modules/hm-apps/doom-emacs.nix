/*
  Package: doom-emacs
  Description: Home Manager activation for Doom Emacs built via marienz/nix-doom-emacs-unstraightened.
  Homepage: https://github.com/doomemacs/doomemacs
  Documentation: https://docs.doomemacs.org/
  Repository: https://github.com/marienz/nix-doom-emacs-unstraightened

  Summary:
    * Imports the upstream Home Manager `homeModule` so `programs.doom-emacs.enable = true` builds Doom with the user's doomdir.
    * Optionally enables the user-level `services.emacs` daemon so the Doom-flavoured Emacs starts on login.

  Notes:
    * Activated only when `programs.doom-emacs.extended.enable = true` in the host NixOS config.
    * Reads doomDir / doomLocalDir / package / enableService from the matching NixOS module so configuration stays in one place.
    * Upstream sets `services.emacs.package` to the Doom build automatically when `programs.doom-emacs.provideEmacs = true` (the default).
*/
_: {
  flake.homeManagerModules.apps.doom-emacs =
    {
      config,
      inputs,
      lib,
      pkgs,
      osConfig,
      ...
    }:
    let
      doomEnabled = lib.attrByPath [
        "programs"
        "doom-emacs"
        "extended"
        "enable"
      ] false osConfig;

      doomCfg = lib.attrByPath [
        "programs"
        "doom-emacs"
        "extended"
      ] { } osConfig;

      doomPackage = doomCfg.package;
      inherit (doomCfg) doomDir enableLanguageTooling enableService;
    in
    {
      imports = [ inputs.nix-doom-emacs-unstraightened.homeModule ];

      config = lib.mkIf doomEnabled {
        programs.doom-emacs = {
          enable = true;
          inherit doomDir;
          doomLocalDir = "${config.xdg.dataHome}/nix-doom";
          emacs = doomPackage;
          # Upstream's default reads `config.programs.{ripgrep,git,fd}.package`;
          # this repo opts those Home Manager wrappers out (`package = null`),
          # so the upstream default would inject null entries that fail
          # `types.listOf types.package`. Source the binaries directly from pkgs.
          extraPackages =
            epkgs:
            lib.optionals enableLanguageTooling [
              (epkgs.treesit-grammars.with-grammars (
                grammars: with grammars; [
                  tree-sitter-bash
                  tree-sitter-c
                  tree-sitter-css
                  tree-sitter-go
                  tree-sitter-html
                  tree-sitter-javascript
                  tree-sitter-jsdoc
                  tree-sitter-json
                  tree-sitter-lua
                  tree-sitter-markdown
                  tree-sitter-markdown-inline
                  tree-sitter-nix
                  tree-sitter-python
                  tree-sitter-rust
                  tree-sitter-toml
                  tree-sitter-tsx
                  tree-sitter-typescript
                  tree-sitter-yaml
                ]
              ))
            ];
          extraBinPackages =
            with pkgs;
            [
              fd
              git
              ripgrep
            ]
            ++ lib.optionals enableLanguageTooling [
              bash-language-server
              biome
              clang-tools
              glow
              go
              gopls
              jq
              lua-language-server
              marksman
              nixd
              nixfmt
              pyright
              ruff
              rust-analyzer
              rustfmt
              shfmt
              stylua
              taplo
              typescript-language-server
              uv
              vscode-langservers-extracted
              yaml-language-server
            ];
        };

        services.emacs.enable = lib.mkDefault enableService;
      };
    };
}
