/*
  Package: bat
  Description: Syntax-highlighted `cat` alternative with Git-aware paging and theming.
  Homepage: https://github.com/sharkdp/bat
  Documentation: https://github.com/sharkdp/bat#usage
  Repository: https://github.com/sharkdp/bat

  Summary:
    * Prints files with syntax highlighting, line numbers, Git integration, and automatic paging via `less`.
    * Supports multiple themes, custom highlighting assets, and convenient diff/line filtering switches.
    * Enhanced with Stylix theming, git integration, and optimized paging behavior.

  Features:
    * Theme automatically synced with Stylix configuration
    * Git diff integration showing file modifications
    * Line numbers and grid for better readability
    * Smart paging (auto-detect when to page)
    * File header showing file name and size

  Options:
    --style=plain,numbers: Control decorations such as line numbers, grid, and header.
    --paging=never|always|auto: Override interaction with the pager.
    --line-range <start>:<end>: Show only the specified lines.
    --list-themes: Enumerate installed highlight themes.
    --diff: Highlight diff hunks passed on stdin with inline change markers.

  Example Usage:
    * `bat README.md` — Preview a Markdown file with syntax highlighting and pager integration.
    * `bat --style=plain --paging=never script.sh` — Emit raw highlighted output directly to stdout.
    * `git diff | bat --diff` — Colorize Git diff output with syntax-aware highlighting.
*/

_: {
  flake.homeManagerModules.apps.bat = {
    programs.bat = {
      enable = true;

      config = {
        # Theme managed by Stylix via stylix.targets.bat

        # Style components to display
        # Options: auto, full, plain, changes, header, header-filename, header-filesize,
        #          grid, rule, numbers, snip
        style = "numbers,changes,header,grid";

        # Paging behavior
        # auto: page if output doesn't fit on screen
        # never: always print to stdout
        # always: always use pager
        paging = "auto";

        # Wrap long lines
        # auto: wrap if terminal is narrow
        # never: don't wrap, scroll horizontally
        # character: wrap at character boundaries
        wrap = "auto";

        # Show non-printable characters
        show-all = false;

        # Tab width
        tabs = "2";

        # Italic text support (requires terminal support)
        italic-text = "always";
      };

      # Custom themes can be added here
      # themes = {
      #   custom-nord = {
      #     src = pkgs.fetchFromGitHub {
      #       owner = "nordtheme";
      #       repo = "sublime-text";
      #       rev = "...";
      #       sha256 = "...";
      #     };
      #     file = "Nord.tmTheme";
      #   };
      # };

      # Custom syntax definitions
      # syntaxes = {
      #   gleam = {
      #     src = pkgs.fetchFromGitHub {
      #       owner = "molnarmark";
      #       repo = "sublime-gleam";
      #       rev = "...";
      #       sha256 = "...";
      #     };
      #     file = "gleam.sublime-syntax";
      #   };
      # };

      # Extra packages that provide syntax highlighting
      # extraPackages = with pkgs.bat-extras; [
      #   batdiff  # diff with bat
      #   batman   # man pages with bat
      #   batgrep  # grep with bat
      #   batwatch # watch with bat
      # ];
    };
  };
}
