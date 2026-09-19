{
  flake.homeManagerModules.zsh =
    { lib, ... }:
    let
      helpers = {
        psgrep = ''ps aux | grep-smart -v grep | grep-smart "$@"'';
        portgrep = ''sudo ss -HQtulnp | grep-smart "$@"'';
        hgrep = ''fc -l 1 | grep-smart "$@"'';
        envgrep = ''env | grep-smart "$@"'';
        gip = ''grep-smart -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" "$@"'';
        gemail = ''grep-smart -oE "\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b" "$@"'';
        gurl = ''grep-smart -oE "https?://[^[:space:]]+" "$@"'';
        gphone = ''grep-smart -oE "\b[0-9]{3}[-.]?[0-9]{3}[-.]?[0-9]{4}\b" "$@"'';
        gpy = ''grep-smart -r --include="*.py" "$@"'';
        gjs = ''grep-smart -r --include="*.js" "$@"'';
        gcss = ''grep-smart -r --include="*.css" "$@"'';
        ghtml = ''grep-smart -r --include="*.html" "$@"'';
        gjson = ''grep-smart -r --include="*.json" "$@"'';
        gxml = ''grep-smart -r --include="*.xml" "$@"'';
        gyml = ''grep-smart -r --include="*.yml" --include="*.yaml" "$@"'';
        gconf = ''grep-smart -r --include="*.conf" --include="*.config" "$@"'';
        glog = ''grep-smart -r --include="*.log" "$@"'';
        # The markers are upper case; under grep-smart's -i, BUG would also match "debug".
        gtodo = ''grep-smart --no-ignore-case -rn "TODO\|FIXME\|HACK\|XXX\|BUG" "$@"'';
        gfunc = ''grep-smart -rn "function\|def\|class" "$@"'';
        gimport = ''grep-smart -rn "import\|require\|include" "$@"'';
        gerr = ''grep-smart -i "error\|warn\|fail\|exception" "$@"'';
      };
    in
    {
      programs.zsh = {
        shellAliases = {
          grep = "grep-smart";
          egrep = "grep-smart -E";
          fgrep = "grep-smart -F";
          grepr = "grep-smart -r";
          grepri = "grep-smart -ri";
          grepn = "grep-smart -n";
          grepv = "grep-smart -v";
          grepc = "grep-smart -c";
          grepl = "grep-smart -l";
          grepL = "grep-smart -L";
          grepw = "grep-smart -w";
          grepx = "grep-smart -x";
          greprin = "grep-smart -rin";
          greprnw = "grep-smart -rnw";
          grep1 = "grep-smart -C1";
          grep3 = "grep-smart -C3";
          grep5 = "grep-smart -C5";
          grepb = "grep-smart -a";
          grepI = "grep-smart -I";
        };

        # zsh's own completion function for grep is named _grep; grep-smart avoids shadowing it.
        initContent = ''
          grep-smart() {
            local -a exclude=(--exclude-dir={.git,.svn,.hg,.bzr,CVS,.idea,.tox,node_modules,__pycache__,.pytest_cache,.mypy_cache})
            # Case-insensitive by default.
            command grep --color=auto "''${exclude[@]}" -i "$@"
          }
          compdef grep-smart=grep

          ${lib.concatStrings (lib.mapAttrsToList (name: body: "${name}() { ${body} }\n") helpers)}
        '';
      };
    };
}
