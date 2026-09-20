/*
  Owner zsh, managed by Home Manager.

  Every file under modules/shell/zsh/ extends `flake.homeManagerModules.zsh`.
  The `lib.mkOrder` slots they use sit between Home Manager's own:
  570 compinit, 700 autosuggestions, 900 plugins, 950 setopt, 1000 tool
  integrations, 1100 aliases, 1200 syntax highlighting.
*/
{ config, ... }:
{
  flake.homeManagerModules.base.imports = [ config.flake.homeManagerModules.zsh ];

  flake.homeManagerModules.zsh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      date = lib.getExe' pkgs.coreutils "date";
      mv = lib.getExe' pkgs.coreutils "mv";
    in
    {
      # A dotDir that is a symlink into another tree would get its files replaced in place there.
      home.activation.zshDotDirSymlink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        zsh_dot_dir=${lib.escapeShellArg config.programs.zsh.dotDir}
        if [[ -L $zsh_dot_dir ]]; then
          run ${mv} -- "$zsh_dot_dir" "$zsh_dot_dir.$(${date} +%Y%m%d%H%M%S).''${HOME_MANAGER_BACKUP_EXT:-hm.bk}"
        fi
      '';

      programs.zsh = {
        enable = true;
        # The XDG default needs xdg.enable, which only the pentesting devshell sets.
        dotDir = "${config.xdg.configHome}/zsh";
        autocd = true;

        history = {
          path = "${config.xdg.dataHome}/zsh/history";
          size = 2147483647;
          extended = true;
          ignoreAllDups = true;
          ignorePatterns = [
            "ls *"
            "eza *"
            "cd .."
            "clear"
            "pwd"
            "zsh"
            "exit"
            "7z"
            "mpv"
            "vim"
            "nvim"
            "* --help"
          ];
        };

        setOptions = [
          "AUTO_PUSHD"
          "PUSHD_IGNORE_DUPS"
          "PUSHD_MINUS"
          "PUSHD_SILENT"
          "PUSHD_TO_HOME"
          "AUTO_REMOVE_SLASH"
          "CHASE_LINKS"
          "EXTENDED_GLOB"
          "NO_CASE_GLOB"
          "NUMERIC_GLOB_SORT"
          "RC_EXPAND_PARAM"
          "CORRECT"
          "CORRECT_ALL"
          "NO_CLOBBER"
          "NO_CHECK_JOBS"
          "NO_BEEP"
          "HIST_REDUCE_BLANKS"
          "HIST_VERIFY"
        ];

        localVariables = {
          REPORTTIME = 5;
          FUNCNEST = 1000;
        };

        initContent = lib.mkMerge [
          ''
            # bash sets HOSTNAME on its own; tools that read it expect it under zsh too.
            export HOSTNAME="$HOST"
          ''

          (lib.mkOrder 1400 ''
            # EXTENDED_GLOB reads '#' as a repetition operator, which breaks flake refs such as nixpkgs#hello.
            disable -p '#'
            # atuin init turns this on; runs after it so '#' stays literal at the prompt.
            unsetopt interactive_comments
          '')
        ];
      };
    };
}
