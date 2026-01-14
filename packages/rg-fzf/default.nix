{
  lib,
  writeShellApplication,
  ripgrep,
  fzf,
  bat,
  coreutils,
  gnused,
}:

writeShellApplication {
  name = "rg-fzf";

  meta = {
    description = "Interactive ripgrep with fzf live search and preview";
    longDescription = ''
      Combines ripgrep and fzf for interactive fuzzy searching across files.

      Features:
      - Live search: re-runs ripgrep as you type
      - Syntax-highlighted preview with bat
      - Opens selected result in $EDITOR at the matching line
      - Respects .gitignore by default

      Usage:
        rg-fzf [INITIAL_QUERY] [DIRECTORY]

      Keybindings:
        Enter     - Open selected file in $EDITOR at line
        Ctrl-/    - Toggle preview window
        Ctrl-u/f  - Scroll preview up/down
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "rg-fzf";
  };

  runtimeInputs = [
    ripgrep
    fzf
    bat
    coreutils
    gnused
  ];

  text = /* bash */ ''
    # Initial query and search directory (optional arguments)
    INITIAL_QUERY="''${1:-}"
    SEARCH_DIR="''${2:-.}"

    # Ripgrep command template for fzf reload
    # {q} is replaced by fzf with the current query
    RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case"

    # Run fzf in live-reload mode
    selected=$(
      fzf --ansi \
          --disabled \
          --query "$INITIAL_QUERY" \
          --bind "start:reload:$RG_PREFIX {q} $SEARCH_DIR || true" \
          --bind "change:reload:sleep 0.1; $RG_PREFIX {q} $SEARCH_DIR || true" \
          --delimiter : \
          --preview 'bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || echo "No preview available"' \
          --preview-window 'right:60%:+{2}-5:wrap' \
          --layout reverse \
          --border rounded \
          --height 80% \
          --info inline \
          --prompt '  rg> ' \
          --pointer '▶' \
          --bind 'ctrl-/:toggle-preview' \
          --bind 'ctrl-u:preview-page-up' \
          --bind 'ctrl-f:preview-page-down' \
      || true
    )

    # Exit if no selection
    if [[ -z "$selected" ]]; then
      exit 0
    fi

    # Parse file:line:column:content format
    file=$(echo "$selected" | cut -d: -f1)
    line=$(echo "$selected" | cut -d: -f2)

    # Validate file exists
    if [[ ! -f "$file" ]]; then
      echo "Error: File not found: $file" >&2
      exit 1
    fi

    # Determine editor (respect $EDITOR, fallback to nvim)
    editor="''${EDITOR:-nvim}"

    # Open in editor at line (most editors support +N syntax)
    exec "$editor" "+$line" "$file"
  '';
}
