/*
  Package: nixvim
  Description: Declarative Neovim configuration powered by the nix-community/nixvim module collection.
  Homepage: https://github.com/nix-community/nixvim
  Documentation: https://nix-community.github.io/nixvim
  Repository: https://github.com/nix-community/nixvim

  Summary:
    * Exposes Neovim configuration as Nix options so editor state, plugins, and key maps stay reproducible.
    * Provides first-class modules for plugin ecosystems (treesitter, LSP, UI helpers) and integrates with Stylix theming targets.
    * Comprehensive setup with LSP, treesitter, telescope, file explorer, and productivity plugins.

  Notes:
    * Imports the upstream Home Manager nixvim module from `inputs.nixvim` and layers Stylix' nixvim target when enabled.
    * LSP servers and treesitter parsers are enabled for common languages (Nix, Rust, Python, JS/TS, Go, Bash, Markdown).
    * Telescope for fuzzy finding, nvim-tree for file exploration, which-key for keybinding discovery.
*/

{
  flake.homeManagerModules.apps.nixvim =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib) mkDefault;
    in
    {
      imports = [ inputs.nixvim.homeModules.nixvim ];

      programs.nixvim = {
        enable = true;

        # Leader key
        globals.mapleader = mkDefault " ";
        globals.maplocalleader = mkDefault " ";

        # Editor options
        opts = {
          # Line numbers
          number = true;
          relativenumber = true;

          # Indentation
          tabstop = 2;
          shiftwidth = 2;
          expandtab = true;
          smartindent = true;

          # Search
          ignorecase = true;
          smartcase = true;
          hlsearch = true;
          incsearch = true;

          # UI
          termguicolors = true;
          signcolumn = "yes";
          cursorline = true;
          scrolloff = 8;
          sidescrolloff = 8;
          wrap = false;

          # Splits
          splitright = true;
          splitbelow = true;

          # Other
          swapfile = false;
          backup = false;
          undofile = true;
          updatetime = 250;
          timeoutlen = 300;
          completeopt = "menu,menuone,noselect";
        };

        # Clipboard integration
        clipboard = {
          providers.wl-copy.enable = true;
          register = "unnamedplus";
        };

        dependencies.glow.enable = true;

        # Plugins configuration
        plugins = {
          # LSP Configuration
          lsp = {
            enable = true;

            servers = {
              # Nix
              nil_ls.enable = true;

              # Rust
              rust_analyzer = {
                enable = true;
                installCargo = false;
                installRustc = false;
              };

              # Python
              pyright.enable = true;

              # JavaScript/TypeScript
              ts_ls.enable = true;

              # Go
              gopls.enable = true;

              # Bash
              bashls.enable = true;

              # Markdown
              marksman.enable = true;

              # YAML
              yamlls.enable = true;

              # JSON
              jsonls.enable = true;
            };

            keymaps = {
              diagnostic = {
                "<leader>e" = "open_float";
                "[d" = "goto_prev";
                "]d" = "goto_next";
              };

              lspBuf = {
                "gd" = "definition";
                "gD" = "declaration";
                "gi" = "implementation";
                "gr" = "references";
                "K" = "hover";
                "<leader>rn" = "rename";
                "<leader>ca" = "code_action";
                "<leader>f" = "format";
              };
            };
          };

          # Completion
          cmp = {
            enable = true;
            autoEnableSources = true;

            settings = {
              mapping = {
                "<C-Space>" = "cmp.mapping.complete()";
                "<C-d>" = "cmp.mapping.scroll_docs(-4)";
                "<C-f>" = "cmp.mapping.scroll_docs(4)";
                "<C-e>" = "cmp.mapping.close()";
                "<CR>" = "cmp.mapping.confirm({ select = true })";
                "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
                "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
              };

              sources = [
                { name = "nvim_lsp"; }
                { name = "path"; }
                { name = "buffer"; }
              ];
            };
          };

          # Treesitter for syntax highlighting
          treesitter = {
            enable = true;
            nixvimInjections = true;
            settings = {
              highlight.enable = true;
              indent.enable = true;
              incremental_selection.enable = true;
            };

            grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
              bash
              c
              go
              json
              lua
              markdown
              nix
              python
              rust
              toml
              typescript
              vim
              vimdoc
              yaml
            ];
          };

          # Telescope fuzzy finder
          telescope = {
            enable = true;

            keymaps = {
              "<leader>ff" = {
                action = "find_files";
                options.desc = "Find files";
              };
              "<leader>fg" = {
                action = "live_grep";
                options.desc = "Live grep";
              };
              "<leader>fb" = {
                action = "buffers";
                options.desc = "Find buffers";
              };
              "<leader>fh" = {
                action = "help_tags";
                options.desc = "Help tags";
              };
              "<leader>fr" = {
                action = "oldfiles";
                options.desc = "Recent files";
              };
            };
          };

          # File explorer
          nvim-tree = {
            enable = true;

            settings = {
              disable_netrw = true;
            };
          };

          # Git signs
          gitsigns = {
            enable = true;

            settings = {
              current_line_blame = false;
              signs = {
                add.text = "+";
                change.text = "~";
                delete.text = "_";
                topdelete.text = "‾";
                changedelete.text = "~";
              };
            };
          };

          # Comment plugin
          comment = {
            enable = true;
          };

          # Auto pairs
          nvim-autopairs.enable = true;

          # Which-key for keybinding help
          which-key = {
            enable = true;
          };

          # Glow markdown preview
          glow = {
            enable = true;
            lazyLoad.enable = true;
            lazyLoad.settings.ft = "markdown";
            settings = {
              border = "rounded";
              width = 120;
              glow_path = null;
            };
          };

          # Lazy loading
          lz-n.enable = true;

          # Status line (uses Stylix theme)
          lualine = {
            enable = true;
          };

          # Buffer line
          bufferline = {
            enable = true;
          };

          # Web devicons (required by nvim-tree, telescope, bufferline, lualine)
          web-devicons.enable = true;
        };

        # Keymaps
        keymaps = [
          # File tree
          {
            mode = "n";
            key = "<leader>e";
            action = "<cmd>NvimTreeToggle<CR>";
            options.desc = "Toggle file explorer";
          }

          # Clear search highlighting
          {
            mode = "n";
            key = "<leader>h";
            action = "<cmd>nohlsearch<CR>";
            options.desc = "Clear search highlight";
          }

          # Buffer navigation
          {
            mode = "n";
            key = "<Tab>";
            action = "<cmd>bnext<CR>";
            options.desc = "Next buffer";
          }
          {
            mode = "n";
            key = "<S-Tab>";
            action = "<cmd>bprevious<CR>";
            options.desc = "Previous buffer";
          }
          {
            mode = "n";
            key = "<leader>bd";
            action = "<cmd>bdelete<CR>";
            options.desc = "Delete buffer";
          }

          # Window navigation
          {
            mode = "n";
            key = "<C-h>";
            action = "<C-w>h";
            options.desc = "Move to left window";
          }
          {
            mode = "n";
            key = "<C-j>";
            action = "<C-w>j";
            options.desc = "Move to bottom window";
          }
          {
            mode = "n";
            key = "<C-k>";
            action = "<C-w>k";
            options.desc = "Move to top window";
          }
          {
            mode = "n";
            key = "<C-l>";
            action = "<C-w>l";
            options.desc = "Move to right window";
          }

          # Window resizing
          {
            mode = "n";
            key = "<C-Up>";
            action = "<cmd>resize +2<CR>";
            options.desc = "Increase window height";
          }
          {
            mode = "n";
            key = "<C-Down>";
            action = "<cmd>resize -2<CR>";
            options.desc = "Decrease window height";
          }
          {
            mode = "n";
            key = "<C-Left>";
            action = "<cmd>vertical resize -2<CR>";
            options.desc = "Decrease window width";
          }
          {
            mode = "n";
            key = "<C-Right>";
            action = "<cmd>vertical resize +2<CR>";
            options.desc = "Increase window width";
          }

          # Glow markdown preview
          {
            mode = [
              "n"
              "v"
            ];
            key = "<M-V>";
            action = "<cmd>Glow<CR>";
            options = {
              desc = "Open Glow markdown preview";
              silent = true;
            };
          }
          {
            mode = "n";
            key = "<leader>V";
            action = "<cmd>Glow!<CR>";
            options = {
              desc = "Close Glow markdown preview";
              silent = true;
            };
          }

          # Visual mode indent
          {
            mode = "v";
            key = "<";
            action = "<gv";
            options.desc = "Indent left";
          }
          {
            mode = "v";
            key = ">";
            action = ">gv";
            options.desc = "Indent right";
          }

          # Move lines in visual mode
          {
            mode = "v";
            key = "J";
            action = ":m '>+1<CR>gv=gv";
            options.desc = "Move line down";
          }
          {
            mode = "v";
            key = "K";
            action = ":m '<-2<CR>gv=gv";
            options.desc = "Move line up";
          }
        ];
      };
    };
}
