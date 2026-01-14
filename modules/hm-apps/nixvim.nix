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
      osConfig,
      ...
    }:
    let
      inherit (lib) mkDefault;
      hostname = osConfig.networking.hostName;
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
          swapfile = true;
          backup = false;
          undofile = true;
          updatetime = 250;
          timeoutlen = 300;
          completeopt = "menu,menuone,noselect";
        };

        # Clipboard integration
        clipboard = {
          providers = {
            xsel.enable = true;
            wl-copy.enable = true;
          };
          register = "unnamedplus,unnamed";
        };

        # Diagnostic display configuration
        diagnostic.settings = {
          virtual_text = {
            prefix = "●";
            spacing = 2;
          };
          signs = {
            text = {
              "__rawKey__vim.diagnostic.severity.ERROR" = "";
              "__rawKey__vim.diagnostic.severity.WARN" = "";
              "__rawKey__vim.diagnostic.severity.INFO" = "";
              "__rawKey__vim.diagnostic.severity.HINT" = "";
            };
          };
          underline = true;
          update_in_insert = false;
          severity_sort = true;
          float = {
            border = "rounded";
            source = true;
          };
        };

        dependencies.glow.enable = true;

        # Otter configuration:
        # 1. Deferred activation - prevents blocking UI while otter creates buffers/attaches LSPs
        # 2. Diagnostic filter - suppresses otter diagnostics for .nix files (''${ causes false positives)
        extraConfigLua = ''
          -- Filter otter diagnostics for nix files only
          -- Intercepts vim.diagnostic.set() which is how otter forwards diagnostics
          local orig_diagnostic_set = vim.diagnostic.set
          vim.diagnostic.set = function(namespace, bufnr, diagnostics, opts)
            local ns_info = vim.diagnostic.get_namespace(namespace)
            local ns_name = ns_info and ns_info.name or ""
            local buf_name = vim.api.nvim_buf_get_name(bufnr)

            if ns_name:match("^otter%-lang%-") and buf_name:match("%.nix$") then
              return
            end

            return orig_diagnostic_set(namespace, bufnr, diagnostics, opts)
          end

          -- Deferred otter activation to prevent blocking UI on file open
          -- Highlighting loads immediately, LSP features follow after delay
          vim.api.nvim_create_autocmd("FileType", {
            pattern = { "nix", "markdown", "quarto", "rmd" },
            callback = function(args)
              vim.defer_fn(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then return end
                local ok, otter = pcall(require, "otter")
                if ok then
                  otter.activate()
                end
              end, 150)
            end,
          })
        '';

        # hmts.nvim - enhanced treesitter injections for Home Manager/Nix files
        # Detects embedded languages via /* lang */ comments, shebangs, and filename inference
        extraPlugins = [ pkgs.vimPlugins.hmts-nvim ];

        # Plugins configuration
        plugins = {
          # LSP Configuration
          lsp = {
            enable = true;

            servers = {
              nixd = {
                enable = true;
                settings = {
                  nixpkgs.expr = "import <nixpkgs> {}";
                  options = {
                    # NixOS options - works in any flake with nixosConfigurations
                    nixos.expr = /* nix */ ''
                      let
                        flake = builtins.getFlake (toString ./.);
                        hosts = flake.nixosConfigurations or {};
                        # Try current hostname first, then first available, then empty
                        host = hosts.${hostname} or (builtins.head (builtins.attrValues hosts)) or null;
                      in
                        if host != null then host.options else {}
                    '';

                    # Home-manager options - standalone homeConfigurations
                    home-manager.expr = /* nix */ ''
                      let
                        flake = builtins.getFlake (toString ./.);
                        configs = flake.homeConfigurations or {};
                        first = if configs != {} then builtins.head (builtins.attrValues configs) else null;
                      in
                        if first != null then first.options else {}
                    '';

                    # Flake-parts options - requires debug = true in the flake
                    flake-parts.expr = /* nix */ ''
                      let
                        flake = builtins.getFlake (toString ./.);
                      in
                        flake.debug.options or flake.currentSystem.options or {}
                    '';
                  };
                };
              };

              # Rust
              rust_analyzer = {
                enable = true;
                installCargo = false;
                installRustc = false;
                settings.check.command = "clippy";
              };

              # Python
              pyright = {
                enable = true;
                settings.python.analysis = {
                  typeCheckingMode = "basic";
                  autoImportCompletions = true;
                };
              };

              # Python linting + formatting (replaces flake8, black, isort)
              ruff.enable = true;

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

              # Lua
              lua_ls.enable = true;

              # TOML
              taplo.enable = true;

              # HTML
              html.enable = true;

              # CSS
              cssls.enable = true;
            };

            keymaps = {
              diagnostic = {
                "<leader>dl" = "open_float";
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
              css
              go
              html
              javascript
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

            settings = {
              defaults = {
                # Layout for better preview
                layout_strategy = "horizontal";
                layout_config = {
                  horizontal = {
                    preview_width = 0.6;
                    prompt_position = "top";
                  };
                };
                sorting_strategy = "ascending";

                # Enhanced ripgrep arguments for live_grep
                vimgrep_arguments = [
                  "rg"
                  "--color=never"
                  "--no-heading"
                  "--with-filename"
                  "--line-number"
                  "--column"
                  "--smart-case"
                  "--trim" # Strip leading whitespace
                ];

                initial_mode = "normal";

                # Keymaps inside telescope picker
                mappings = {
                  # Insert mode (typing search query)
                  i = {
                    "<Esc>".__raw = "function() vim.cmd('stopinsert') end";
                    "<C-j>".__raw = "require('telescope.actions').move_selection_next";
                    "<C-k>".__raw = "require('telescope.actions').move_selection_previous";
                    "<C-u>".__raw = "require('telescope.actions').preview_scrolling_up";
                    "<C-d>".__raw = "require('telescope.actions').preview_scrolling_down";
                    "<C-q>".__raw =
                      "require('telescope.actions').send_to_qflist + require('telescope.actions').open_qflist";
                  };
                  # Normal mode (vim-like navigation)
                  n = {
                    # Navigation
                    j.__raw = "require('telescope.actions').move_selection_next";
                    k.__raw = "require('telescope.actions').move_selection_previous";
                    H.__raw = "require('telescope.actions').move_to_top";
                    M.__raw = "require('telescope.actions').move_to_middle";
                    L.__raw = "require('telescope.actions').move_to_bottom";
                    gg.__raw = "require('telescope.actions').move_to_top";
                    G.__raw = "require('telescope.actions').move_to_bottom";

                    # Preview scrolling
                    "<C-u>".__raw = "require('telescope.actions').preview_scrolling_up";
                    "<C-d>".__raw = "require('telescope.actions').preview_scrolling_down";

                    # Actions
                    "<CR>".__raw = "require('telescope.actions').select_default";
                    l.__raw = "require('telescope.actions').select_default";
                    o.__raw = "require('telescope.actions').select_default";
                    "<C-x>".__raw = "require('telescope.actions').select_horizontal";
                    "<C-v>".__raw = "require('telescope.actions').select_vertical";
                    "<C-t>".__raw = "require('telescope.actions').select_tab";

                    # Quickfix
                    "<C-q>".__raw =
                      "require('telescope.actions').send_to_qflist + require('telescope.actions').open_qflist";

                    # Close
                    q.__raw = "require('telescope.actions').close";
                    "<Esc>".__raw = "require('telescope.actions').close";

                    # Back to insert mode to refine search
                    i.__raw = "function() vim.cmd('startinsert') end";
                    "/".__raw = "function() vim.cmd('startinsert') end";
                  };
                };
              };

              pickers = {
                live_grep = {
                  # Show hidden files but respect .gitignore
                  additional_args = [
                    "--hidden"
                    "--glob"
                    "!.git/"
                  ];
                };
                find_files = {
                  hidden = true;
                  follow = true;
                };
              };
            };

            keymaps = {
              "<leader>ff" = {
                action = "find_files";
                options.desc = "Find files";
              };
              "<leader>fg" = {
                action = "live_grep";
                options.desc = "Live grep";
              };
              "<leader>fw" = {
                action = "grep_string";
                options.desc = "Grep word under cursor";
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
              "<leader>f/" = {
                action = "current_buffer_fuzzy_find";
                options.desc = "Fuzzy find in buffer";
              };
              "<leader>f." = {
                action = "resume";
                options.desc = "Resume last search";
              };
              "<leader>fd" = {
                action = "diagnostics";
                options.desc = "Find diagnostics";
              };
              "<leader>fk" = {
                action = "keymaps";
                options.desc = "Find keymaps";
              };
            };
          };

          # File explorer
          nvim-tree = {
            enable = true;

            settings = {
              disable_netrw = true;
              hijack_netrw = true;
              hijack_directories = {
                enable = false; # Don't auto-open when opening directories
              };
              actions = {
                open_file = {
                  quit_on_open = false; # Keep tree open when opening file from tree
                  window_picker = {
                    enable = true;
                  };
                };
              };
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

          # Otter - LSP features for embedded languages (e.g., bash in writeShellApplication)
          # Works with hmts.nvim: hmts detects languages via injection queries, otter provides LSP
          # Activation deferred in extraConfigLua to prevent blocking UI on file open
          # Diagnostics filtered in extraConfigLua to suppress shellcheck ''${ false positives for nix
          otter = {
            enable = true;
            autoActivate = false; # Manual deferred activation in extraConfigLua

            settings = {
              handle_leading_whitespace = true;

              buffers = {
                set_filetype = true;
                write_to_disk = false;
              };

              lsp = {
                diagnostic_update_events = [
                  "BufWritePost"
                  "InsertLeave"
                ];
              };
            };
          };

          # Format on save
          conform-nvim = {
            enable = true;
            settings = {
              format_on_save = {
                timeout_ms = 500;
                lsp_format = "fallback";
              };
              formatters_by_ft = {
                python = [ "ruff_format" ];
                bash = [ "shfmt" ];
                sh = [ "shfmt" ];
                nix = [ "nixfmt" ];
                lua = [ "stylua" ];
                toml = [ "taplo" ];
                # Biome: JS/TS/JSON/CSS (faster than prettier)
                javascript = [ "biome" ];
                typescript = [ "biome" ];
                javascriptreact = [ "biome" ];
                typescriptreact = [ "biome" ];
                json = [ "biome" ];
                jsonc = [ "biome" ];
                css = [ "biome" ];
                # Prettier: languages biome doesn't support
                yaml = [ "prettier" ];
                markdown = [ "prettier" ];
                html = [ "prettier" ];
                # Rust uses rustfmt via rust-analyzer (lsp_format fallback)
                # Go uses gofmt via gopls (lsp_format fallback)
              };
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
            settings.options.offsets = [
              {
                filetype = "NvimTree";
                text = "File Explorer";
                highlight = "Directory";
                separator = true;
              }
            ];
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

          # Show keymaps
          {
            mode = "n";
            key = "<leader>k";
            action = "<cmd>Telescope keymaps<CR>";
            options.desc = "Search keymaps";
          }
          {
            mode = "n";
            key = "<leader>K";
            action = "<cmd>WhichKey<CR>";
            options.desc = "WhichKey menu";
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

      # Stylix nixvim target - keep main background opaque for consistency
      # Transparent elements inherit from Normal, so they show the correct color
      stylix.targets.nixvim.transparentBackground = {
        main = true;
        signColumn = true; # Inherit from Normal
        numberLine = true; # Inherit from Normal (but not CursorLineNr)
      };
    };
}
