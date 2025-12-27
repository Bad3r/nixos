/*
  Package: fzf
  Description: General-purpose command-line fuzzy finder for interactive filtering of lists and files.
  Homepage: https://junegunn.github.io/fzf/
  Documentation: https://github.com/junegunn/fzf#usage
  Repository: https://github.com/junegunn/fzf

  Summary:
    * Offers blazing fast fuzzy search with ANSI color, multi-select, preview, and key binding integrations across shells and editors.
    * Provides shell widgets and completion hooks so `Ctrl-T`, `Ctrl-R`, and custom bindings open interactive pickers within your shell session.
    * Enhanced with bat preview, fd integration, and custom keybindings for improved workflow.

  Features:
    * File preview with syntax highlighting via bat
    * Directory preview with tree or eza
    * fd integration for fast file/directory finding
    * Custom keybindings (ctrl-a: select all, ctrl-d: deselect all, ctrl-/: toggle preview)
    * Colors automatically synced with Stylix theme

  Shell integrations:
    * Ctrl-T: Find files in current directory
    * Ctrl-R: Search command history
    * Alt-C: Change directory interactively
*/

{
  flake.homeManagerModules.apps.fzf =
    { pkgs, lib, ... }:
    {
      programs.fzf = {
        enable = true;

        # Shell integrations
        enableZshIntegration = true;
        enableBashIntegration = true;
        enableFishIntegration = false;

        # Use fd for file/directory finding (faster and respects .gitignore)
        defaultCommand = "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
        fileWidgetCommand = "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
        changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d --hidden --follow --exclude .git";

        # Default options
        defaultOptions = [
          # Layout
          "--height 60%"
          "--layout=reverse"
          "--border=rounded"
          "--info=inline"

          # Preview window
          "--preview-window=right:50%:wrap"

          # Multi-select
          "--multi"

          # Prompt and pointer
          "--prompt='  '"
          "--pointer='▶'"
          "--marker='✓'"

          # Performance
          "--bind 'ctrl-/:toggle-preview'"
          "--bind 'ctrl-a:select-all'"
          "--bind 'ctrl-d:deselect-all'"
          "--bind 'ctrl-u:preview-page-up'"
          "--bind 'ctrl-f:preview-page-down'"
        ];

        # File preview with bat
        fileWidgetOptions = [
          "--preview '${pkgs.bat}/bin/bat --style=numbers --color=always --line-range=:500 {}'"
        ];

        # Directory preview with eza or tree
        changeDirWidgetOptions = [
          "--preview '${pkgs.eza}/bin/eza --tree --level=2 --color=always {} | head -200'"
        ];

        # History search with preview showing command
        historyWidgetOptions = [
          "--preview 'echo {}'"
          "--preview-window=down:3:wrap"
        ];

        # Colors automatically managed by stylix.targets.fzf
      };

      # Environment variables for fzf integration
      home.sessionVariables = {
        # Use fd for fzf's default command
        FZF_DEFAULT_COMMAND = lib.mkDefault "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";

        # Options for Ctrl-T (file widget)
        FZF_CTRL_T_COMMAND = lib.mkDefault "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
        FZF_CTRL_T_OPTS = lib.mkDefault (
          lib.concatStringsSep " " [
            "--preview '${pkgs.bat}/bin/bat --style=numbers --color=always --line-range=:500 {}'"
            "--preview-window=right:60%"
          ]
        );

        # Options for Alt-C (directory widget)
        FZF_ALT_C_COMMAND = lib.mkDefault "${pkgs.fd}/bin/fd --type d --hidden --follow --exclude .git";
        FZF_ALT_C_OPTS = lib.mkDefault (
          lib.concatStringsSep " " [
            "--preview '${pkgs.eza}/bin/eza --tree --level=2 --color=always {} | head -200'"
            "--preview-window=right:60%"
          ]
        );
      };
    };
}
