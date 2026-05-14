/*
  Package: path
  Description: Interactive shell function that resolves paths and copies a comma-delimited result to the X clipboard.
  Homepage: nil
  Documentation: nil
  Repository: nil

  Summary:
    * Resolves one or more path arguments with realpath and prints each absolute path to stdout.
    * Copies the same resolved paths to the X CLIPBOARD selection as a comma-delimited line.

  Options:
    <path>: Resolve the path with realpath. Pass multiple paths to copy a comma-delimited clipboard payload.

  Notes:
    * The xsel binary is referenced by absolute store path through the
      `programs.path.extended.package` option, so the function works
      without xsel on the user's PATH and is independent of
      `programs.xsel.extended.enable`.
    * zsh and bash completions are left file-oriented so tab completion
      continues to select paths after the `path` command name.
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

      zshCompletion = ''
        if [ -n "''${ZSH_VERSION-}" ] && type compdef >/dev/null 2>&1; then
          compdef _files path
        fi
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
        programs.zsh.interactiveShellInit = lib.mkAfter ''
          ${pathFunction}
          ${zshCompletion}
        '';

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
