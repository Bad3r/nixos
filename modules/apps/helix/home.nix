/*
  Package: helix
  Description: Post-modern modal text editor.
  Homepage: https://helix-editor.com
  Documentation: https://docs.helix-editor.com
  Repository: https://github.com/helix-editor/helix

  Summary:
    * Modal editing with multiple selections as a core feature.
    * Built-in language server support.

  Options:
    -h: Print help.
    -c: Specify a config file.
*/
_: {
  flake.homeManagerModules.apps.helix =
    {
      config,
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "helix" "extended" "enable" ] false osConfig;
      colors = config.lib.stylix.colors.withHashtag;
      vscode = import ../../stylix/_vscode-dark-2026.nix;
      hostname = osConfig.networking.hostName;

      # Helix pipes the buffer over stdin and reads the result from stdout.
      # Biome selects its parser from the (dummy) file extension. Matches the
      # `biome` formatter used by treefmt (modules/meta/treefmt.nix).
      biomeFormatter = ext: {
        command = "biome";
        args = [
          "format"
          "--stdin-file-path=stdin.${ext}"
        ];
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        stylix.targets.helix.enable = false;

        programs.helix = {
          enable = true;
          package = osConfig.programs.helix.extended.package;
          defaultEditor = false;

          # Language servers and formatters are placed on hx's PATH only: the HM
          # module wraps hx with `--suffix PATH`, so these are not installed into
          # the global environment.
          extraPackages = with pkgs; [
            # Nix
            nixd
            nixfmt
            # Rust
            rust-analyzer
            # Python
            pyright
            ruff
            # Go
            gopls
            # JavaScript / TypeScript / web
            typescript-language-server
            typescript
            vscode-langservers-extracted
            biome
            # Bash
            bash-language-server
            shfmt
            shellcheck
            # Markdown
            marksman
            (mdformat.withPlugins (ps: [ ps.mdformat-gfm ]))
            # YAML
            yaml-language-server
            yamlfmt
            # TOML
            taplo
            # Lua
            lua-language-server
            stylua
          ];

          themes.vscode_dark_2026 = {
            inherits = "github_dark";
            palette = {
              "canvas.default" = colors.base00;
              "border.default" = colors.base02;
            };
            "ui.text" = vscode.foreground;
            "ui.text.focus" = colors.base05;
            "ui.text.inactive" = vscode.disabledForeground;
            "ui.text.directory" = vscode."textLink.foreground";
            "ui.background.separator" = colors.base02;
            "ui.linenr" = vscode."editorLineNumber.foreground";
            "ui.linenr.selected" = colors.base05;
            "ui.virtual" = "#3a3b3c";
            "ui.virtual.ruler".bg = vscode."editor.lineHighlightBackground";
            "ui.statusline" = {
              fg = colors.base04;
              bg = colors.base01;
            };
            "ui.statusline.active" = {
              fg = colors.base05;
              bg = colors.base01;
            };
            "ui.statusline.normal" = {
              fg = vscode."statusBarItem.prominentForeground";
              bg = vscode."editor.selectionBackground";
            };
            "ui.statusline.insert" = {
              fg = vscode."statusBarItem.prominentForeground";
              bg = vscode."statusBarItem.prominentBackground";
            };
            "ui.menu" = {
              fg = colors.base05;
              bg = vscode."editorWidget.background";
            };
            "ui.menu.selected".bg = vscode."editorSuggestWidget.selectedBackground";
            "ui.menu.scroll" = {
              fg = vscode.disabledForeground;
              bg = vscode."editorWidget.background";
            };
            "ui.popup".bg = vscode."editorWidget.background";
            "ui.popup.info" = {
              fg = colors.base05;
              bg = vscode."editorWidget.background";
            };
            "ui.help" = {
              fg = colors.base05;
              bg = vscode."editorWidget.background";
            };
            "ui.selection".bg = "#1d4a5c";
            "ui.selection.primary".bg = vscode."editor.selectionBackground";
            "ui.cursorline.primary".bg = vscode."editor.lineHighlightBackground";
            "markup.link.text" = {
              fg = vscode."textLink.foreground";
              modifiers = [ "underlined" ];
            };
          };

          settings = {
            # VS Code Dark 2026 look (GitHub Dark syntax, Dark 2026 UI greys).
            theme = "vscode_dark_2026";

            editor = {
              line-number = "relative";
              cursorline = true;
              scrolloff = 8;
              color-modes = true;
              bufferline = "multiple";
              # Override truecolor autodetection false-negatives (e.g. under tmux).
              true-color = true;
              cursor-shape = {
                normal = "block";
                insert = "bar";
                select = "underline";
              };
              indent-guides.render = true;
              # Show dotfiles in the picker; useful in a dotfiles/Nix config repo.
              file-picker.hidden = false;
              lsp.display-messages = true;
              statusline.left = [
                "mode"
                "spinner"
                "version-control"
                "file-name"
                "read-only-indicator"
                "file-modification-indicator"
              ];
            };
          };

          # Merged over Helix's built-in languages.toml, so only overrides are set.
          languages = {
            language-server = {
              # Deep nixd integration: completion and docs for nixpkgs plus this
              # flake's NixOS / home-manager / flake-parts option sets.
              nixd = {
                command = "nixd";
                config = {
                  nixpkgs.expr = "import <nixpkgs> {}";
                  options = {
                    nixos.expr = ''
                      let
                        flake = builtins.getFlake (toString ./.);
                        hosts = flake.nixosConfigurations or {};
                        # A chained `or` after a parenthesized call is the "cursed or"
                        # (application of the identifier `or`), so use explicit if/else.
                        host =
                          if hosts ? "${hostname}" then
                            hosts."${hostname}"
                          else if hosts != { } then
                            builtins.head (builtins.attrValues hosts)
                          else
                            null;
                      in
                        if host != null then host.options else {}
                    '';
                    home-manager.expr = ''
                      let
                        flake = builtins.getFlake (toString ./.);
                        configs = flake.homeConfigurations or {};
                        first = if configs != {} then builtins.head (builtins.attrValues configs) else null;
                      in
                        if first != null then first.options else {}
                    '';
                    flake-parts.expr = ''
                      let
                        flake = builtins.getFlake (toString ./.);
                      in
                        flake.debug.options or flake.currentSystem.options or {}
                    '';
                  };
                };
              };

              rust-analyzer.config.check.command = "clippy";

              pyright.config.python.analysis = {
                typeCheckingMode = "basic";
                autoImportCompletions = true;
              };
            };

            language = [
              {
                name = "nix";
                auto-format = true;
                language-servers = [ "nixd" ];
                formatter.command = "nixfmt";
              }
              {
                name = "python";
                auto-format = true;
                # Override Helix defaults (ty/jedi/pylsp); ruff also formats.
                language-servers = [
                  "pyright"
                  "ruff"
                ];
              }
              {
                name = "rust";
                auto-format = true;
              }
              {
                name = "go";
                auto-format = true;
              }
              {
                name = "bash";
                auto-format = true;
                formatter = {
                  command = "shfmt";
                  args = [
                    "-i"
                    "2"
                    "-s"
                    "-"
                  ];
                };
              }
              {
                name = "lua";
                auto-format = true;
                formatter = {
                  command = "stylua";
                  args = [
                    "--indent-type"
                    "Spaces"
                    "--indent-width"
                    "2"
                    "--column-width"
                    "120"
                    "-"
                  ];
                };
              }
              {
                name = "toml";
                auto-format = true;
                formatter = {
                  command = "taplo";
                  args = [
                    "fmt"
                    "--option"
                    "column_width=120"
                    "--option"
                    "reorder_keys=false"
                    "--option"
                    "indent_string=  "
                    "-"
                  ];
                };
              }
              {
                name = "yaml";
                auto-format = true;
                formatter = {
                  command = "yamlfmt";
                  args = [ "-" ];
                };
              }
              {
                name = "markdown";
                auto-format = true;
                formatter = {
                  command = "mdformat";
                  args = [
                    "--wrap"
                    "keep"
                    "--number"
                    "-"
                  ];
                };
              }
              {
                name = "json";
                auto-format = true;
                formatter = biomeFormatter "json";
              }
              {
                name = "jsonc";
                auto-format = true;
                formatter = biomeFormatter "jsonc";
              }
              {
                name = "css";
                auto-format = true;
                formatter = biomeFormatter "css";
              }
              {
                name = "html";
                auto-format = true;
                formatter = biomeFormatter "html";
              }
              {
                name = "javascript";
                auto-format = true;
                formatter = biomeFormatter "js";
              }
              {
                name = "jsx";
                auto-format = true;
                formatter = biomeFormatter "jsx";
              }
              {
                name = "typescript";
                auto-format = true;
                formatter = biomeFormatter "ts";
              }
              {
                name = "tsx";
                auto-format = true;
                formatter = biomeFormatter "tsx";
              }
            ];
          };
        };
      };
    };
}
