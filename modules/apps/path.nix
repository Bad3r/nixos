/*
  Package: path
  Description: Interactive shell function that resolves paths and copies a comma-delimited result to the X clipboard.
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Prints each resolved absolute path to stdout.
*/
_:
let
  PathModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.path.extended;
      realpathBin = lib.getExe' pkgs.coreutils "realpath";
      xselBin = lib.getExe' cfg.package "xsel";

      pathFunction = ''
        # path: print realpath output and copy a comma-delimited version to
        # the X CLIPBOARD selection via xsel.
        path() {
          if [ "$#" -eq 0 ]; then
            printf 'path: usage: path <path> [path...]\n' >&2
            return 64
          fi

          local resolved_paths
          resolved_paths=$(${realpathBin} -- "$@")
          local realpath_rc=$?

          if [ -n "$resolved_paths" ]; then
            printf '%s\n' "$resolved_paths"
          fi

          if [ "$realpath_rc" -ne 0 ]; then
            return "$realpath_rc"
          fi

          local clipboard_payload
          clipboard_payload="''${resolved_paths//$'\n'/, }"

          printf '%s' "$clipboard_payload" | ${xselBin} --clipboard --input
          local xsel_rc=$?
          if [ "$xsel_rc" -ne 0 ]; then
            printf 'path: xsel exited %s; clipboard not updated\n' \
              "$xsel_rc" >&2
            return "$xsel_rc"
          fi
        }
      '';

      # On fpath, so it registers under whichever compinit runs: the global one or a user's own.
      zshCompletion = pkgs.writeTextDir "share/zsh/site-functions/_path" ''
        #compdef path
        _files
      '';

      bashCompletion = ''
        if [ -n "''${BASH_VERSION-}" ]; then
          complete -o default -o bashdefault path 2>/dev/null || true
        fi
      '';
    in
    {
      options.programs.path.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to install the `path` interactive shell function in zsh
            and bash. The xsel dependency is pinned via
            `programs.path.extended.package` and is not resolved from the
            user's PATH.
          '';
        };

        package = lib.mkPackageOption pkgs "xsel" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ zshCompletion ];

        programs.zsh.interactiveShellInit = lib.mkAfter pathFunction;

        programs.bash.interactiveShellInit = lib.mkAfter ''
          ${pathFunction}
          ${bashCompletion}
        '';
      };
    };
in
{
  flake.nixosModules.apps.path = PathModule;
}
