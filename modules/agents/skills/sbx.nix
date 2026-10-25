_:
let
  skillBody = ''
    ## When To Use

    - Unknown binaries, downloaded archives and installers, and repositories you
      do not trust, when you need to run their scripts or inspect what they do.
    - Checks of what such code does to a machine: files it writes, processes it
      starts, what its display shows (`sbx screenshot`).

    The `nixos` base carries coreutils, bash, `file`, `git`, `perl`, `python3`,
    and `unzip`; it has no compiler, no `make`, and no network. Fetch inputs on
    the host into `$TMPDIR` without running them, then copy them in.

    ## When Not To Use

    - NixOS configuration tests: use the NixOS test driver
      (`pkgs.testers.runNixOSTest`) or `nixos-rebuild build-vm`.
    - Offline one-shots of an OCI image: use `podman --module untrusted run`.

    ## One-Shot Work

    `sbx run` creates a sandbox, copies inputs in, runs the command, copies
    outputs out, and destroys the sandbox even when a step fails. Prefer it to
    the create/exec/destroy sequence.

    ```bash
    sbx run nixos --in "$TMPDIR/dl/tool" --out /root/report.txt --to "$TMPDIR" -- sh -c 'python3 tool/check.py > report.txt'
    ```

    - `--in PATH` (repeatable) copies a host path into `/root/`, the command's
      working directory.
    - `--out GUEST_PATH` (repeatable) needs `--to DIR`, a host directory.
    - Host paths sit under the caller's git checkout, `~/trees`, or `$TMPDIR`; a
      copy out never overwrites an existing target.
    - `--timeout 10m` bounds the command; `--ttl`, `--mem`, and `--cpus` size the
      sandbox within the host ceilings.

    Run `sbx` as its own command, without `cd ... &&`, pipes, redirections, or
    an env prefix, and set the directory through the tool's working-directory
    parameter. Codex runs only such a bare `sbx` outside its own sandbox.

    ## Verbs

    | Verb                                         | Effect                                     |
    | -------------------------------------------- | ------------------------------------------ |
    | `run <base> [flags] -- CMD`                  | create, copy in, exec, copy out, destroy   |
    | `create <base> [--name N] [--ttl 30m]`       | start a sandbox and wait for SSH           |
    | `exec <name> [--timeout T] [--agent] -- CMD` | run over SSH; `--agent` uses qemu-ga       |
    | `cp <src> [<dst>]`                           | one side `<name>:<path>`; no dst = `xfer`  |
    | `destroy <name>` / `--mine` / `--expired`    | stop and delete sandboxes                  |
    | `list [--mine]`, `info <name>`               | state, CID, TTL left, `xfer` directory     |
    | `screenshot <name> [--ocr]`                  | display to PNG or PPM in `xfer`, opt. OCR  |
    | `base list`, `base build <base>`             | show or build Nix bases                    |
    | `gc [--dry-run]`                             | remove expired and orphaned sandboxes      |

    Destroy the sandboxes you create by name. `--mine` matches every sandbox of
    the Claude Code session or Codex thread, its subagents' included.

    ## JSON Contract

    Pass `--json` before `--`; after it, the flag belongs to the guest command.
    stdout is then one JSON document.

    - `exec`: `{exit_code, stdout, stderr, truncated, timed_out}`.
    - `run`: `{sandbox, in, exec, out}`, with `exec` shaped as above.
    - `exec` and `run` exit with the guest command's status, 124 after
      `--timeout`; 255 can also mean SSH to the guest failed.
    - Failures print `{"error": {"code", "message"}}` and exit 1, or 2 for a
      usage error. A copy out that fails after the command ran makes `run`
      fail this way, and the command's result is lost. `base-missing` means
      `sbx base build <base>` comes first.

    ## MCP Tools

    The `sbx` MCP server offers each verb as a tool (`base list` is
    `base_list`). Flags become named arguments, the guest command an argv
    list, and the result is the `--json` document above; a refusal is a tool
    error carrying the error object. A failing guest command is no tool error:
    read `exit_code`.

    - The checkout copy root and relative host paths follow the directory the
      client started in, not your working directory; give absolute paths.
    - Claude Code hands the server its session when it starts it, so after
      `/clear` the tools' `mine` matches the old session until `/mcp`
      reconnects `sbx`.
  '';
in
{
  flake.lib.agents._internal.skills.raw.sbx = {
    name = "sbx";
    title = "Disposable Sandboxes With sbx";
    description = "Run unknown binaries, downloads, and untrusted repositories in a disposable sbx VM: when to use it, its verbs, and the --json contract.";
    app = "sbx";
    body = skillBody;

    codex = {
      openaiYaml.interface = {
        display_name = "sbx Sandboxes";
        short_description = "Run untrusted code in a disposable VM";
        default_prompt = "Use $sbx to run untrusted code in a disposable sbx VM.";
      };
    };

    claude = {
      frontmatter."allowed-tools" = "Bash(sbx *), Read";
    };
  };
}
