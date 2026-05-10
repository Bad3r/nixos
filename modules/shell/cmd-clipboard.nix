/*
  Shell function: ccp (Command Copy)

  Description:
    Runs a command and copies both the command line and its captured
    output to the X11 clipboard via xsel, while also displaying the
    output on the terminal. Works in interactive bash and zsh sessions.

  Usage:
    ccp <command> [args...]

  Example:
    $ ccp hostname
    $ hostname
    tpnix
    # Clipboard contains:
    #   $ hostname
    #   tpnix

  Notes:
    * Wired through `environment.interactiveShellInit`, which NixOS folds
      into both `programs.bash.interactiveShellInit` and
      `programs.zsh.interactiveShellInit`. The function syntax used is
      compatible with both shells (POSIX function, `local`, `printf %q`,
      and process substitution `>(...)`).
    * Captures stderr alongside stdout (`2>&1`) so error messages also
      land in the clipboard.
    * Aliases at the call site are NOT expanded (e.g. `ccp ls` runs the
      `ls` binary, not an `ls=eza` alias). Pass the underlying command.
    * Requires `xsel`; both hosts enable it via apps-enable.nix.
*/
{
  flake.nixosModules.base = {
    environment.interactiveShellInit = ''
      # ccp <command> [args...] - run a command, show its output on the
      # terminal, and copy "$ command\n<output>\n" to the X11 clipboard.
      ccp() {
        if ! command -v xsel >/dev/null 2>&1; then
          printf 'ccp: xsel not found in PATH\n' >&2
          return 127
        fi
        if [ "$#" -eq 0 ]; then
          printf 'usage: ccp <command> [args...]\n' >&2
          return 2
        fi
        local _ccp_quoted="" _ccp_arg
        for _ccp_arg in "$@"; do
          if [ -z "$_ccp_quoted" ]; then
            _ccp_quoted=$(printf '%q' "$_ccp_arg")
          else
            _ccp_quoted="$_ccp_quoted $(printf '%q' "$_ccp_arg")"
          fi
        done
        { printf '$ %s\n' "$_ccp_quoted"; "$@"; } 2>&1 | tee >(xsel -ib >/dev/null)
      }
    '';
  };
}
