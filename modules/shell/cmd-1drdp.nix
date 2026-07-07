/*
  Shell function: 1drdp (One Identity Safeguard RDP launcher)

  Description:
    Opens a One Identity Safeguard `.rdp` connection file in Remmina with the
    fixed `sg` placeholder password injected, so Remmina connects without
    showing the credentials prompt. Safeguard `.rdp` files carry a one-time
    launch token in the `username` field but no password field, so Remmina
    prompts for a password that is never validated by the target. The token
    authenticates the session; `sg` is the dummy password those Safeguard
    connections accept.

    The function copies the file to a temporary path, appends a
    `password:s:sg` line (Remmina's RDP importer maps that to the connection
    password, see plugins/rdp/rdp_file.c), and launches `remmina -c` on the
    copy so the original download is left untouched.

  Usage:
    1drdp <file.rdp>

  Example:
    $ 1drdp data/SG-10.49.52.250_fwadmin2.rdp

  Notes:
    * Wired through `environment.interactiveShellInit`, which NixOS folds into
      both `programs.bash.interactiveShellInit` and
      `programs.zsh.interactiveShellInit`. The function syntax is POSIX and
      works in both shells; the `1drdp` name (leading digit) is accepted by
      bash and zsh.
    * The `\r\n` line ending matches the CRLF Safeguard `.rdp` files; Remmina
      strips the terminator on import, so the password is exactly `sg`.
    * `remmina -c` reads the file synchronously before returning (it blocks on
      the first instance and returns after the running instance imports the
      file), so removing the temporary copy immediately after is safe.
    * A URI (`rdp://user:pass@host`) cannot carry the RemoteApp fields that the
      Safeguard launcher needs, and there is no `remmina` connect-time password
      flag, which is why the password is injected into the file instead.
*/
{
  flake.nixosModules.base = {
    environment.interactiveShellInit = ''
      # 1drdp <file.rdp> - open a One Identity Safeguard RDP file in Remmina
      # with the fixed 'sg' placeholder password injected so it does not prompt.
      1drdp() {
        if [ "$#" -ne 1 ]; then
          printf 'usage: 1drdp <file.rdp>\n' >&2
          return 2
        fi
        if ! command -v remmina >/dev/null 2>&1; then
          printf '1drdp: remmina not found in PATH\n' >&2
          return 127
        fi
        if [ ! -r "$1" ]; then
          printf '1drdp: cannot read %s\n' "$1" >&2
          return 1
        fi
        local _1drdp_tmp
        _1drdp_tmp=$(mktemp --suffix=.rdp) || return 1
        if ! cp -- "$1" "$_1drdp_tmp"; then
          rm -f -- "$_1drdp_tmp"
          return 1
        fi
        printf '\r\npassword:s:sg\r\n' >>"$_1drdp_tmp"
        local _1drdp_status
        remmina -c "$_1drdp_tmp"
        _1drdp_status=$?
        rm -f -- "$_1drdp_tmp"
        return "$_1drdp_status"
      }
    '';
  };
}
