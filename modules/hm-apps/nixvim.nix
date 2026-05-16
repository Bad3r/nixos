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

_: {
  # Upstream akinsho/git-conflict.nvim ships no LICENSE file, so nixpkgs flags
  # the plugin as unfree. The allowlist entry is required for evaluation until
  # upstream publishes a license.
  nixpkgs.allowedUnfreePackages = [
    "cheatsheet.nvim"
    "git-conflict.nvim"
  ];

  flake.homeManagerModules.apps.nixvim =
    {
      inputs,
      lib,
      pkgs,
      osConfig,
      ...
    }:
    let
      inherit (lib) mkDefault mkIf;
      nvimEnabled = lib.attrByPath [ "programs" "neovim" "extended" "enable" ] false osConfig;
      nvimPkg = lib.attrByPath [
        "programs"
        "neovim"
        "extended"
        "package"
      ] pkgs.neovim-unwrapped osConfig;
      hostname = osConfig.networking.hostName;
      kittyEnabled = lib.attrByPath [ "programs" "kitty" "extended" "enable" ] false osConfig;
    in
    {
      imports = lib.optionals nvimEnabled [ inputs.nixvim.homeModules.nixvim ];

      config =
        if nvimEnabled then
          {
            # Use navarasu/onedark.nvim directly instead of stylix's base16 mapping
            stylix.targets.nixvim.enable = false;

            programs.nixvim = {
              enable = true;
              package = nvimPkg;
              viAlias = true;
              vimAlias = true;
              defaultEditor = true;

              colorschemes.onedark.enable = true;

              # Nixvim builds its own pkgs instance, so the system-level
              # allowUnfreePredicate doesn't apply. Forward it so unfree
              # plugins listed in `nixpkgs.allowedUnfreePackages` are honored.
              nixpkgs.config.allowUnfreePredicate = pkgs.config.allowUnfreePredicate;

              # Leader keys, plus a runtime-gated OSC52 clipboard provider
              # when Neovim is running in kitty.
              globals = {
                mapleader = mkDefault " ";
                maplocalleader = mkDefault " ";
                clipboard = mkIf kittyEnabled {
                  __raw = ''
                    (function()
                      if vim.env.KITTY_WINDOW_ID == nil then
                        return nil
                      end
                      return "osc52"
                    end)()
                  '';
                };
              };

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

              # JSONL: route `.jsonl` and `.ndjson` onto the jsonl filetype so
              # the treesitter alias and conform formatter below apply.
              filetype.extension = {
                jsonl = "jsonl";
                ndjson = "jsonl";
              };

              # Clipboard integration. `globals.clipboard` above forces
              # Neovim's built-in OSC52 provider inside kitty; outside kitty,
              # `vim.g.clipboard` stays unset and Neovim picks one of these
              # providers via standard autodetection.
              clipboard = {
                register = "unnamedplus,unnamed";
                providers = {
                  xsel.enable = true;
                  wl-copy.enable = true;
                };
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
              # 2. Automatic activation is limited to buffers that actually contain injected languages,
              #    so plain Nix files avoid the extra LSP fan-out while embedded shell/Lua/etc. still work
              # 3. Diagnostic filter - suppresses otter diagnostics for .nix files (''${ causes false positives)
              extraConfigLua = ''
                -- Scratch buffer auto-naming: assign timestamped names to unnamed buffers
                -- so swap files become identifiable and recoverable after crashes.
                -- On first save, the filename is enriched with a slug from the buffer content.
                local scratch_augroup = vim.api.nvim_create_augroup("nvim_scratch_naming", { clear = true })
                local swap_dir = vim.fn.stdpath("cache") .. "/swap"
                vim.fn.mkdir(swap_dir, "p")

                -- `//` suffix tells Vim to encode the full file path into the
                -- swap filename, so files sharing a basename never collide.
                vim.opt.directory = swap_dir .. "//"

                local function assign_scratch_name(buf)
                  if vim.api.nvim_buf_get_name(buf) ~= "" then return end
                  if vim.bo[buf].buftype ~= "" then return end
                  if not vim.bo[buf].modifiable then return end
                  if not vim.bo[buf].buflisted then return end
                  if vim.b[buf].scratch_named then return end

                  local stamp = os.date("%Y-%m-%d-%H%M%S")
                  local rand = string.format("%04x", vim.uv.hrtime() % 0x10000)
                  local path = string.format("scratch-%s-%s.md", stamp, rand)
                  vim.api.nvim_buf_set_name(buf, path)
                  vim.b[buf].scratch_named = true
                end

                vim.api.nvim_create_autocmd("BufEnter", {
                  group = scratch_augroup,
                  callback = function(args)
                    vim.schedule(function()
                      if vim.api.nvim_buf_is_valid(args.buf) then
                        assign_scratch_name(args.buf)
                      end
                    end)
                  end,
                })

                vim.api.nvim_create_autocmd("BufWritePost", {
                  group = scratch_augroup,
                  callback = function(args)
                    if not vim.b[args.buf].scratch_named then return end
                    if vim.b[args.buf].scratch_slugified then return end

                    local name = vim.api.nvim_buf_get_name(args.buf)
                    local basename = vim.fn.fnamemodify(name, ":t")
                    if not basename:match("^scratch%-%d%d%d%d%-%d%d%-%d%d%-%d%d%d%d%d%d%-%x%x%x%x%.md$") then return end

                    local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 20, false)
                    local first = ""
                    for _, line in ipairs(lines) do
                      if line:match("%S") then
                        first = line
                        break
                      end
                    end
                    if first == "" then return end

                    local slug = first:lower()
                      :gsub("[^%w]+", "-")
                      :gsub("^-+", "")
                      :gsub("-+$", "")
                      :sub(1, 40)
                      :gsub("-+$", "")
                    if slug == "" then return end

                    local old_path = name
                    local new_path = name:gsub("%.md$", "-" .. slug .. ".md")
                    if new_path == old_path then return end

                    local ok = vim.uv.fs_rename(old_path, new_path)
                    if not ok then return end
                    vim.api.nvim_buf_set_name(args.buf, new_path)
                    vim.b[args.buf].scratch_slugified = true
                  end,
                })

                -- Window-local Arabic viewing helpers for mixed RTL/LTR content.
                local function set_arabic_view(enabled)
                  if enabled then
                    if vim.w.arabic_view_state == nil then
                      vim.w.arabic_view_state = {
                        wrap = vim.wo.wrap,
                        linebreak = vim.wo.linebreak,
                        breakindent = vim.wo.breakindent,
                        rightleftcmd = vim.wo.rightleftcmd,
                        sidescrolloff = vim.wo.sidescrolloff,
                      }
                    end

                    vim.go.arabicshape = true
                    vim.cmd("setlocal rightleft")
                    vim.opt_local.rightleftcmd = "search"
                    vim.wo.wrap = true
                    vim.wo.linebreak = true
                    vim.wo.breakindent = true
                    vim.wo.sidescrolloff = 0
                  else
                    local state = vim.w.arabic_view_state
                    vim.cmd("setlocal norightleft")

                    if state ~= nil then
                      vim.wo.wrap = state.wrap
                      vim.wo.linebreak = state.linebreak
                      vim.wo.breakindent = state.breakindent
                      vim.opt_local.rightleftcmd = state.rightleftcmd
                      vim.wo.sidescrolloff = state.sidescrolloff
                      vim.w.arabic_view_state = nil
                    end
                  end
                end

                vim.api.nvim_create_user_command("ArabicView", function(opts)
                  local arg = opts.args ~= "" and opts.args or "toggle"

                  if arg == "split" then
                    vim.cmd("vsplit")
                    set_arabic_view(true)
                    return
                  end

                  if arg == "on" then
                    set_arabic_view(true)
                  elseif arg == "off" then
                    set_arabic_view(false)
                  elseif arg == "toggle" then
                    set_arabic_view(not vim.wo.rightleft)
                  else
                    vim.notify("ArabicView expects on, off, toggle, or split", vim.log.levels.ERROR)
                  end
                end, {
                  nargs = "?",
                  complete = function()
                    return { "on", "off", "toggle", "split" }
                  end,
                  desc = "Toggle Arabic-friendly window view",
                })

                vim.keymap.set("n", "<leader>ua", "<cmd>ArabicView toggle<CR>", {
                  desc = "Toggle Arabic view",
                  silent = true,
                })
                vim.keymap.set("n", "<leader>uA", "<cmd>ArabicView split<CR>", {
                  desc = "Arabic view split",
                  silent = true,
                })

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

                local function otter_has_injected_languages(bufnr)
                  local main_lang = vim.bo[bufnr].filetype
                  local parser_lang = vim.treesitter.language.get_lang(main_lang)
                  if parser_lang == nil then
                    return false
                  end

                  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, parser_lang)
                  if not ok_parser or parser == nil then
                    return false
                  end

                  local ok_parse = pcall(parser.parse, parser, true)
                  if not ok_parse then
                    return false
                  end

                  local injectable = rawget(_G, "OtterConfig") and OtterConfig.injectable_languages or {}
                  local seen = {}
                  for _, lang in ipairs(injectable) do
                    seen[lang] = true
                  end

                  local function has_injected_tree(lang_tree)
                    for lang, child_tree in pairs(lang_tree:children()) do
                      if lang ~= main_lang and seen[lang] then
                        return true
                      end
                      if has_injected_tree(child_tree) then
                        return true
                      end
                    end
                    return false
                  end

                  return has_injected_tree(parser)
                end

                -- Deferred otter activation to prevent blocking UI on file open.
                -- Use the target buffer explicitly so delayed activation does not race into
                -- whichever buffer happens to be current 150ms later.
                vim.api.nvim_create_autocmd("FileType", {
                  pattern = { "nix", "markdown", "quarto", "rmd" },
                  callback = function(args)
                    vim.defer_fn(function()
                      if not vim.api.nvim_buf_is_valid(args.buf) or not vim.api.nvim_buf_is_loaded(args.buf) then
                        return
                      end
                      if not otter_has_injected_languages(args.buf) then
                        return
                      end
                      local ok, otter = pcall(require, "otter")
                      if ok then
                        vim.api.nvim_buf_call(args.buf, function()
                          if vim.bo[args.buf].buftype ~= "" then
                            return
                          end
                          otter.activate()
                        end)
                      end
                    end, 150)
                  end,
                })

                -- diffview: diagonal slashes for diff filler lines (lower visual noise than '-')
                vim.opt.fillchars:append({ diff = "╱" })

                -- :DvStash → quick stash inspector (per USAGE.md recipe)
                vim.api.nvim_create_user_command("DvStash", function()
                  vim.cmd("DiffviewFileHistory -g --range=stash")
                end, { desc = "Inspect git stash via diffview" })

                -- JSONL has no dedicated grammar, so reuse JSON's. The whole
                -- file is not a single JSON document, but treesitter's error
                -- recovery still highlights each object correctly across the
                -- newline separators.
                vim.treesitter.language.register("json", "jsonl")

                require("cheatsheet").setup({})
              '';

              # plenary.nvim is added explicitly because the pinned nixvim/nixpkgs
              # combination does not currently pull telescope's runtime dependency
              # onto the packpath.
              extraPlugins = [
                pkgs.vimPlugins.cheatsheet-nvim
                pkgs.vimPlugins.plenary-nvim
              ];

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
                      enable = true;
                      auto_open = true;
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

                # Diff/PR review surface with diffview.nvim
                diffview = {
                  enable = true;

                  lazyLoad = {
                    enable = true;
                    settings.cmd = [
                      "DiffviewOpen"
                      "DiffviewClose"
                      "DiffviewFocusFiles"
                      "DiffviewToggleFiles"
                      "DiffviewRefresh"
                      "DiffviewLog"
                      "DiffviewFileHistory"
                    ];
                  };

                  settings = {
                    enhanced_diff_hl = true;
                    show_help_hints = false;

                    default_args = {
                      DiffviewOpen = [
                        "--imply-local"
                        "-uno"
                      ];
                    };

                    # Suppress the default "✓" done glyph for an icon-free panel.
                    signs.done = "";

                    view = {
                      default.winbar_info = true;
                      merge_tool = {
                        layout = "diff3_mixed";
                        winbar_info = true;
                      };
                      file_history.winbar_info = true;
                    };

                    file_panel.tree_options.folder_statuses = "always";

                    # Function form: re-evaluated each open so the float tracks
                    # terminal resizes instead of locking to startup dimensions.
                    commit_log_panel.win_config.__raw = ''
                      function()
                        local width = math.floor(vim.o.columns * 0.8)
                        local height = math.floor(vim.o.lines * 0.8)
                        return {
                          type = "float",
                          relative = "editor",
                          border = "rounded",
                          width = width,
                          height = height,
                          row = math.floor((vim.o.lines - height) / 2),
                          col = math.floor((vim.o.columns - width) / 2),
                        }
                      end
                    '';

                    hooks = {
                      diff_buf_read.__raw = ''
                        function(_)
                          vim.opt_local.wrap = false
                          vim.opt_local.list = false
                          vim.opt_local.colorcolumn = "80"
                          vim.opt_local.cursorline = false
                          vim.opt_local.signcolumn = "no"
                        end
                      '';
                    };

                    keymaps = {
                      file_panel = [
                        {
                          mode = "n";
                          key = "cc";
                          action.__raw = ''
                            function()
                              vim.ui.input({ prompt = "Commit message: " }, function(msg)
                                if not msg or msg == "" then return end
                                vim.system(
                                  { "git", "commit", "-m", msg },
                                  { text = true },
                                  vim.schedule_wrap(function(out)
                                    if out.code == 0 then
                                      vim.notify("Committed", vim.log.levels.INFO)
                                      vim.cmd("DiffviewRefresh")
                                    else
                                      vim.notify(
                                        "git commit failed: " .. (out.stderr or ""),
                                        vim.log.levels.ERROR
                                      )
                                    end
                                  end)
                                )
                              end)
                            end
                          '';
                          description = "Commit staged changes";
                        }
                        {
                          mode = "n";
                          key = "ca";
                          action.__raw = ''
                            function()
                              vim.ui.input({ prompt = "Amend commit (empty=no-edit): " }, function(msg)
                                local args = { "git", "commit", "--amend" }
                                if not msg or msg == "" then
                                  table.insert(args, "--no-edit")
                                else
                                  table.insert(args, "-m")
                                  table.insert(args, msg)
                                end
                                vim.system(args, { text = true }, vim.schedule_wrap(function(out)
                                  if out.code == 0 then
                                    vim.notify("Amended", vim.log.levels.INFO)
                                    vim.cmd("DiffviewRefresh")
                                  else
                                    vim.notify(
                                      "git commit --amend failed: " .. (out.stderr or ""),
                                      vim.log.levels.ERROR
                                    )
                                  end
                                end))
                              end)
                            end
                          '';
                          description = "Amend last commit";
                        }
                        {
                          mode = "n";
                          key = "<esc>";
                          action.__raw = "require('diffview.actions').close";
                          description = "Close diffview";
                        }
                      ];
                      file_history_panel = [
                        {
                          mode = "n";
                          key = "<esc>";
                          action.__raw = "require('diffview.actions').close";
                          description = "Close diffview";
                        }
                      ];
                    };
                  };
                };

                # Magit-style git interface, backed by diffview for inline diffs
                neogit = {
                  enable = true;
                  lazyLoad = {
                    enable = true;
                    settings.cmd = [ "Neogit" ];
                  };
                  settings = {
                    integrations.diffview = true;
                    graph_style = "unicode";
                  };
                };

                # Three-way merge conflict navigator. Default mappings rebind
                # `co`/`ct`/`cb`/`c0` (and `]x`/`[x`) inside conflict buffers,
                # so vim's `ct{char}` motion is shadowed while markers remain.
                git-conflict = {
                  enable = true;
                  package = pkgs.vimPlugins.git-conflict-nvim;
                  settings = {
                    default_mappings = true;
                    default_commands = true;
                    list_opener = "copen";
                  };
                };

                # Inline GitHub PR/issue review via `gh` CLI
                octo = {
                  enable = true;
                  lazyLoad = {
                    enable = true;
                    settings.cmd = [ "Octo" ];
                  };
                  settings = {
                    picker = "telescope";
                    enable_builtin = true;
                    default_remote = [
                      "upstream"
                      "origin"
                    ];
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

                    lsp.diagnostic_update_events = [ "BufWritePost" ];
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
                      # JSONL: jq -c keeps one value per line
                      jsonl = [ "jq_jsonl" ];
                      # Rust uses rustfmt via rust-analyzer (lsp_format fallback)
                      # Go uses gofmt via gopls (lsp_format fallback)
                    };
                    # jq's default mode pretty-prints, which would collapse
                    # JSONL into one document. `-c` keeps each value compact
                    # and on its own line so the file stays valid JSONL.
                    formatters.jq_jsonl = {
                      command = lib.getExe pkgs.jq;
                      args = [
                        "-c"
                        "."
                      ];
                      stdin = true;
                    };
                  };
                };

                # Lazy loading
                lz-n.enable = true;

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
                  settings.options.style_preset.__raw = "require('bufferline').style_preset.minimal";
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
                {
                  mode = "n";
                  key = "<leader>?";
                  action = "<cmd>Cheatsheet<CR>";
                  options.desc = "Search cheatsheet";
                }

                # Visual selections
                {
                  mode = "n";
                  key = "<leader>vG";
                  action = "VG";
                  options.desc = "Select lines to end of file";
                }
                {
                  mode = "n";
                  key = "<leader>vg";
                  action = "Vgg";
                  options.desc = "Select lines to start of file";
                }
                {
                  mode = "n";
                  key = "<leader>vj";
                  action = "V2j";
                  options.desc = "Select next 3 lines";
                }
                {
                  mode = "n";
                  key = "<leader>vk";
                  action = "V2k";
                  options.desc = "Select previous 3 lines";
                }
                {
                  mode = "n";
                  key = "<leader>va";
                  action = "ggVG";
                  options.desc = "Select entire file";
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

                # Diffview
                {
                  mode = "n";
                  key = "<leader>gd";
                  action = "<cmd>DiffviewOpen<CR>";
                  options.desc = "Diffview: open";
                }
                {
                  mode = "n";
                  key = "<leader>gD";
                  action = "<cmd>DiffviewClose<CR>";
                  options.desc = "Diffview: close";
                }
                {
                  mode = "n";
                  key = "<leader>gh";
                  action = "<cmd>DiffviewFileHistory %<CR>";
                  options.desc = "Diffview: file history (current)";
                }
                {
                  mode = "n";
                  key = "<leader>gH";
                  action = "<cmd>DiffviewFileHistory<CR>";
                  options.desc = "Diffview: file history (all)";
                }
                {
                  mode = "n";
                  key = "<leader>gp";
                  action = "<cmd>DiffviewOpen origin/HEAD...HEAD<CR>";
                  options.desc = "Diffview: PR diff";
                }
                {
                  mode = "n";
                  key = "<leader>gP";
                  action = "<cmd>DiffviewFileHistory --range=origin/HEAD...HEAD --right-only --no-merges<CR>";
                  options.desc = "Diffview: per-commit PR review";
                }
                {
                  mode = "n";
                  key = "<leader>gs";
                  action = "<cmd>DiffviewOpen --staged<CR>";
                  options.desc = "Diffview: staged";
                }
                {
                  mode = "n";
                  key = "<leader>gS";
                  action = "<cmd>DvStash<CR>";
                  options.desc = "Diffview: stash";
                }

                # Neogit
                {
                  mode = "n";
                  key = "<leader>gn";
                  action = "<cmd>Neogit<CR>";
                  options.desc = "Neogit: open";
                }

                # Octo
                {
                  mode = "n";
                  key = "<leader>go";
                  action = "<cmd>Octo<CR>";
                  options.desc = "Octo: PR review";
                }
              ];

            };
          }
        else
          { };
    };
}
