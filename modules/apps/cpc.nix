/*
  Package: cpc (copy command + output)
  Description: Interactive shell function that runs a command, streams its
               combined stdout/stderr to the terminal live, and copies a
               tagged record of the invocation and its output to the X
               CLIPBOARD selection via xsel.

  Usage:
    cpc <command> [args...]
    cpc sudo systemctl status nginx

  Clipboard payload format:
    <command>ip -br a</command>
    <output>
    lo               UNKNOWN        127.0.0.1/8
    </output>

  Notes:
    * The xsel binary is referenced by absolute store path through the
      `programs.cpc.extended.package` option, so the function works
      without xsel on the user's PATH and is independent of
      `programs.xsel.extended.enable`.
    * stdout and stderr are merged so utilities that diagnose to stderr
      (rg, ip, systemctl) end up in the clipboard alongside their results.
    * TTY-aware programs (`ls`, `git`, `grep --color=auto`, pagers) detect
      a pipe on stdout and disable color, paging, and progress output
      because the function captures via `tee`. Force colour with the
      tool's flag if needed (e.g. `cpc git -c color.ui=always status`).
    * Sudo password prompts go to /dev/tty and are not captured.
    * Argv is reconstructed with `printf '%q '` so the recorded command
      round-trips through the shell. Both bash and zsh implement %q in
      their builtin printf.
    * XML-style tags are used for delimitation, not strict XML conformance:
      payload contents are not entity-escaped, so output containing literal
      `<` / `>` / `&` will not parse as XML but remains human-readable.
*/
_:
let
  cpcModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.cpc.extended;
      xselBin = "${cfg.package}/bin/xsel";

      cpcFunction = ''
        # cpc: run a command, tee output to the terminal, and copy a tagged
        # <command>/<output> record to the X CLIPBOARD selection via xsel.
        cpc() {
          if [ "$#" -eq 0 ]; then
            printf 'cpc: usage: cpc <command> [args...]\n' >&2
            return 64
          fi

          # Reconstruct a shell-safe representation of the invocation so the
          # recorded <command> round-trips through the shell. Both bash and
          # zsh implement %q in their builtin printf.
          local cmd_str
          cmd_str=$(printf '%q ' "$@")
          cmd_str=''${cmd_str% }

          # Run the capture inside a subshell so an EXIT trap clears the
          # temp directory even when the user interrupts the function with
          # SIGINT, SIGTERM, or SIGHUP. INT/TERM/HUP simply `exit`, which
          # then fires EXIT and removes the directory. The trap is
          # installed before `mktemp` and guarded with `[ -n "$tmp_dir" ]`
          # so an early signal cannot leak the directory between mktemp's
          # creation and assignment.
          (
            tmp_dir=""
            trap '[ -n "$tmp_dir" ] && rm -rf -- "$tmp_dir"' EXIT
            trap 'exit' INT TERM HUP

            tmp_dir=$(mktemp -d --tmpdir cpc.XXXXXX) || exit 1

            # Inner subshell captures the command's exit code into rc; tee
            # mirrors combined stdout+stderr to the terminal (live) and
            # into out (for the clipboard payload). Sudo password prompts
            # go to /dev/tty and bypass this pipe, so they are never
            # captured.
            ( "$@" 2>&1; printf '%s\n' "$?" >"$tmp_dir/rc" ) | tee "$tmp_dir/out"

            local rc
            rc=$(cat "$tmp_dir/rc" 2>/dev/null)
            : "''${rc:=1}"

            {
              printf '<command>%s</command>\n<output>\n' "$cmd_str"
              cat "$tmp_dir/out"
              printf '</output>\n'
            } | ${xselBin} --clipboard --input
            local xsel_rc=$?
            if [ "$xsel_rc" -ne 0 ]; then
              printf 'cpc: xsel exited %s; clipboard not updated\n' \
                "$xsel_rc" >&2
            fi

            exit "$rc"
          )
        }
      '';
    in
    {
      options.programs.cpc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to install the `cpc` interactive shell function in zsh
            and bash. The xsel dependency is pinned via
            `programs.cpc.extended.package` and is not resolved from the
            user's PATH.
          '';
        };

        package = lib.mkPackageOption pkgs "xsel" { };
      };

      config = lib.mkIf cfg.enable {
        programs.zsh.interactiveShellInit = lib.mkAfter cpcFunction;
        programs.bash.interactiveShellInit = lib.mkAfter cpcFunction;
      };
    };
in
{
  flake.nixosModules.apps.cpc = cpcModule;
}
