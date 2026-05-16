/*
  Internal: generated Doom Emacs file contents
  Description: Renders init.el / config.el / packages.el from Nix data for
  review and future doomdir updates without making the default doomdir a
  derivation.
*/

{ lib }:
let
  inherit (lib)
    concatLines
    concatMapStringsSep
    concatStringsSep
    generators
    isAttrs
    isInt
    isList
    isString
    mapAttrsToList
    ;

  toInit =
    attrs:
    concatLines (
      [ "(doom!" ]
      ++ (mapAttrsToList (
        category: modules:
        concatLines (
          [ ":${category}" ]
          ++ (mapAttrsToList (
            moduleName: value:
            if value == true then
              moduleName
            else if isList value then
              "(${moduleName} ${concatStringsSep " " value})"
            else
              abort "Unsupported Doom module value for ${category}.${moduleName}: ${generators.toPretty { } value}"
          ) modules)
        )
      ) attrs)
      ++ [ ")" ]
    );

  nixdHostLetBindings = [
    "  flake = builtins.getFlake (toString ./.);"
    "  hosts = flake.nixosConfigurations or {};"
    "  hostName = builtins.getEnv \"HOSTNAME\";"
    "  host ="
    "    if hostName != \"\" && builtins.hasAttr hostName hosts then builtins.getAttr hostName hosts"
    "    else if hosts != {} then builtins.head (builtins.attrValues hosts)"
    "    else null;"
  ];

  nixdOptionsExpr =
    extraLetBindings: body:
    concatStringsSep "\n" ([ "let" ] ++ nixdHostLetBindings ++ extraLetBindings ++ [ "in" ] ++ body);

  nixdNixosOptionsExpr = nixdOptionsExpr [ ] [ "  if host != null then host.options else {}" ];

  nixdHomeManagerOptionsExpr =
    nixdOptionsExpr
      [ "  hmUsers = if host != null then host.options.home-manager.users or null else null;" ]
      [
        "  if hmUsers != null && hmUsers ? type && hmUsers.type ? getSubOptions"
        "  then hmUsers.type.getSubOptions []"
        "  else {}"
      ];

  modules = {
    completion = {
      corfu = [ "+orderless" ];
      vertico = true;
    };

    ui = {
      doom = true;
      dashboard = true;
      hl-todo = true;
      modeline = true;
      ophints = true;
      popup = [ "+defaults" ];
      tabs = true;
      treemacs = [ "+lsp" ];
      vc-gutter = [ "+pretty" ];
      vi-tilde-fringe = true;
      window-select = [ "+numbers" ];
      workspaces = true;
    };

    editor = {
      evil = [ "+everywhere" ];
      file-templates = true;
      fold = true;
      format = [
        "+onsave"
        "+lsp"
      ];
      snippets = true;
      whitespace = [
        "+guess"
        "+trim"
      ];
    };

    emacs = {
      dired = true;
      electric = true;
      tramp = true;
      undo = true;
      vc = true;
    };

    checkers = {
      syntax = true;
    };

    tools = {
      eval = [ "+overlay" ];
      lookup = true;
      lsp = true;
      magit = [ "+forge" ];
      tree-sitter = true;
    };

    lang = {
      cc = [ "+tree-sitter" ];
      emacs-lisp = true;
      go = [
        "+lsp"
        "+tree-sitter"
      ];
      javascript = [
        "+lsp"
        "+tree-sitter"
      ];
      json = [
        "+lsp"
        "+tree-sitter"
      ];
      lua = [
        "+lsp"
        "+tree-sitter"
      ];
      markdown = [ "+tree-sitter" ];
      nix = [
        "+lsp"
        "+tree-sitter"
      ];
      org = true;
      python = [
        "+lsp"
        "+pyright"
        "+tree-sitter"
        "+uv"
      ];
      rust = [
        "+lsp"
        "+tree-sitter"
      ];
      sh = [ "+lsp" ];
      web = [
        "+lsp"
        "+tree-sitter"
      ];
      yaml = [
        "+lsp"
        "+tree-sitter"
      ];
    };

    config = {
      default = [
        "+bindings"
        "+smartparens"
      ];
    };
  };

  settings = {
    base = [
      {
        name = "doom-theme";
        value.quotedSymbol = "doom-one";
      }
      {
        name = "display-line-numbers-type";
        value.quotedSymbol = "relative";
      }
      {
        name = "org-directory";
        value = "~/org/";
      }
      {
        name = "tab-width";
        value = 2;
      }
      {
        name = "standard-indent";
        value = 2;
      }
      {
        name = "evil-shift-width";
        value = 2;
      }
      {
        name = "indent-tabs-mode";
        value = false;
      }
      {
        name = "select-enable-clipboard";
        value = true;
      }
      {
        name = "select-enable-primary";
        value = true;
      }
      {
        name = "make-backup-files";
        value = false;
      }
      {
        name = "auto-save-default";
        value = true;
      }
      {
        name = "scroll-margin";
        value = 8;
      }
      {
        name = "hscroll-margin";
        value = 8;
      }
      {
        name = "split-width-threshold";
        value = 120;
      }
      {
        name = "split-height-threshold";
        value = null;
      }
      {
        name = "lsp-disabled-clients";
        value.quotedList = [
          "rnix-lsp"
          "nix-nil"
        ];
      }
      {
        name = "lsp-nix-nixd-server-path";
        value = "nixd";
      }
      {
        name = "lsp-nix-nixd-formatting-command";
        value.vector = [ "nixfmt" ];
      }
      {
        name = "lsp-nix-nixd-nixpkgs-expr";
        value = "import <nixpkgs> {}";
      }
      {
        name = "lsp-nix-nixd-nixos-options-expr";
        value = nixdNixosOptionsExpr;
      }
      {
        name = "lsp-nix-nixd-home-manager-options-expr";
        value = nixdHomeManagerOptionsExpr;
      }
      {
        name = "lsp-rust-analyzer-cargo-watch-command";
        value = "clippy";
      }
      {
        name = "lsp-pyright-type-checking-mode";
        value = "basic";
      }
      {
        name = "lsp-pyright-auto-import-completions";
        value = true;
      }
    ];
  };

  elispValue =
    value:
    if value == true then
      "t"
    else if value == false then
      "nil"
    else if value == null then
      "nil"
    else if isInt value then
      toString value
    else if isString value then
      builtins.toJSON value
    else if isList value then
      "'(${concatStringsSep " " (map elispValue value)})"
    else if isAttrs value && value ? quotedSymbol then
      "'${value.quotedSymbol}"
    else if isAttrs value && value ? quotedList then
      "'(${concatStringsSep " " value.quotedList})"
    else if isAttrs value && value ? vector then
      "[${concatStringsSep " " (map elispValue value.vector)}]"
    else if isAttrs value && value ? raw then
      value.raw
    else
      abort "Unsupported Emacs Lisp value: ${generators.toPretty { } value}";

  renderSetqPair = setting: "${setting.name} ${elispValue setting.value}";

  leaderKeymaps = [
    {
      key = "e";
      desc = "Toggle file explorer";
      command = "+treemacs/toggle";
    }
    {
      key = "h";
      desc = "Clear search highlight";
      command = "evil-ex-nohighlight";
    }
    {
      key = "k";
      desc = "Search keymaps";
      command = "embark-bindings";
    }
    {
      key = "f f";
      desc = "Find file";
      command = "projectile-find-file";
    }
    {
      key = "f g";
      desc = "Search project";
      command = "+default/search-project";
    }
    {
      key = "f w";
      desc = "Search symbol in project";
      command = "+default/search-project-for-symbol-at-point";
    }
    {
      key = "f b";
      desc = "Switch buffer";
      command = "consult-buffer";
    }
    {
      key = "f r";
      desc = "Recent file";
      command = "consult-recent-file";
    }
    {
      key = "f /";
      desc = "Search buffer";
      command = "consult-line";
    }
    {
      key = "f .";
      desc = "Resume search";
      command = "consult-resume";
    }
    {
      key = "d l";
      desc = "List diagnostics";
      command = "flycheck-list-errors";
    }
    {
      key = "r n";
      desc = "Rename symbol";
      command = "lsp-rename";
    }
    {
      key = "c a";
      desc = "Code action";
      command = "lsp-execute-code-action";
    }
    {
      key = "c f";
      desc = "Format buffer";
      command = "+format/region-or-buffer";
    }
    {
      key = "b d";
      desc = "Delete buffer";
      command = "kill-current-buffer";
    }
    {
      key = "g n";
      desc = "Magit status";
      command = "magit-status";
    }
    {
      key = "g s";
      desc = "Magit status";
      command = "magit-status";
    }
    {
      key = "g o";
      desc = "Forge dispatch";
      command = "forge-dispatch";
    }
    {
      key = "u a";
      desc = "Toggle Arabic view";
      command = "vx/arabic-view-toggle";
    }
    {
      key = "u A";
      desc = "Arabic view split";
      command = "vx/arabic-view-split";
    }
  ];

  normalKeymaps = [
    {
      key = "<tab>";
      command = "next-buffer";
    }
    {
      key = "<backtab>";
      command = "previous-buffer";
    }
    {
      key = "C-h";
      command = "evil-window-left";
    }
    {
      key = "C-j";
      command = "evil-window-down";
    }
    {
      key = "C-k";
      command = "evil-window-up";
    }
    {
      key = "C-l";
      command = "evil-window-right";
    }
    {
      key = "C-<up>";
      command = "enlarge-window";
    }
    {
      key = "C-<down>";
      command = "shrink-window";
    }
    {
      key = "C-<left>";
      command = "shrink-window-horizontally";
    }
    {
      key = "C-<right>";
      command = "enlarge-window-horizontally";
    }
    {
      key = "gd";
      command = "+lookup/definition";
    }
    {
      key = "gD";
      command = "lsp-find-declaration";
    }
    {
      key = "gi";
      command = "lsp-find-implementation";
    }
    {
      key = "gr";
      command = "+lookup/references";
    }
    {
      key = "K";
      command = "+lookup/documentation";
    }
    {
      key = "[d";
      command = "flycheck-previous-error";
    }
    {
      key = "]d";
      command = "flycheck-next-error";
    }
  ];

  visualKeymaps = [
    {
      key = "<";
      command = "+evil/shift-left";
    }
    {
      key = ">";
      command = "+evil/shift-right";
    }
  ];

  renderLeaderKeymap =
    keymap: ":desc ${builtins.toJSON keymap.desc} ${builtins.toJSON keymap.key} #'${keymap.command}";

  renderModeKeymap = keymap: "${builtins.toJSON keymap.key} #'${keymap.command}";

  leaderKeymapsEl = concatMapStringsSep "\n" renderLeaderKeymap leaderKeymaps;
  normalKeymapsEl = concatMapStringsSep "\n" renderModeKeymap normalKeymaps;
  visualKeymapsEl = concatMapStringsSep "\n" renderModeKeymap visualKeymaps;

  initEl = concatStringsSep "\n" [
    ";;; init.el -*- lexical-binding: t; -*-"
    ""
    (toInit modules)
  ];

  configEl = ''
    ;;; config.el -*- lexical-binding: t; -*-

    (require 'cl-lib)
    (require 'subr-x)

    (setq ${concatStringsSep "\n      " (map renderSetqPair settings.base)})

    (add-to-list 'auto-mode-alist '("\\.jsonl\\'" . json-ts-mode))
    (add-to-list 'auto-mode-alist '("\\.ndjson\\'" . json-ts-mode))
    (add-to-list 'auto-mode-alist '("\\.toml\\'" . toml-ts-mode))

    (defun vx/arabic-view-on ()
      (interactive)
      (setq-local bidi-paragraph-direction 'right-to-left)
      (visual-line-mode 1))

    (defun vx/arabic-view-off ()
      (interactive)
      (setq-local bidi-paragraph-direction nil)
      (visual-line-mode -1))

    (defun vx/arabic-view-toggle ()
      (interactive)
      (if (eq bidi-paragraph-direction 'right-to-left)
          (vx/arabic-view-off)
        (vx/arabic-view-on)))

    (defun vx/arabic-view-split ()
      (interactive)
      (split-window-right)
      (other-window 1)
      (vx/arabic-view-on))

    (map! :leader
    ${leaderKeymapsEl})

    (map! :n
    ${normalKeymapsEl})

    (map! :v
    ${visualKeymapsEl})

    (after! apheleia
      (set-formatter! 'biome '("biome" "format" "--stdin-file-path" filepath "--html-formatter-enabled=true")
        :modes '(css-mode css-ts-mode
                 html-mode html-ts-mode
                 js-mode js-ts-mode
                 js-json-mode json-mode json-ts-mode
                 typescript-mode typescript-ts-mode tsx-ts-mode
                 web-mode))
      (set-formatter! 'ruff :modes '(python-mode python-ts-mode))
      (set-formatter! 'jq-jsonl '("jq" "-c" ".")
        :modes '((json-mode (and buffer-file-name
                                  (string-match-p "\\.\\(jsonl\\|ndjson\\)\\'" buffer-file-name)))
                 (json-ts-mode (and buffer-file-name
                                     (string-match-p "\\.\\(jsonl\\|ndjson\\)\\'" buffer-file-name)))))
      (set-formatter! 'lsp :modes '(yaml-mode yaml-ts-mode))
      (setq apheleia-mode-alist
            (cl-remove-if
             (lambda (entry)
               (let ((formatter (cdr entry)))
                 (and (symbolp formatter)
                      (string-prefix-p "prettier" (symbol-name formatter)))))
             apheleia-mode-alist))
      (setq apheleia-formatters
            (cl-remove-if
             (lambda (entry)
               (string-prefix-p "prettier" (symbol-name (car entry))))
             apheleia-formatters)))
  '';

  packagesEl = ''
    ;; -*- no-byte-compile: t; -*-
    ;;; packages.el
  '';

  generatedFiles = {
    "config.el" = configEl;
    "init.el" = initEl;
    "packages.el" = packagesEl;
  };
in
{
  inherit
    modules
    settings
    toInit
    generatedFiles
    ;
}
