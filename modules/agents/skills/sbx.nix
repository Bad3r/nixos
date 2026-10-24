_:
let
  skillBody = ''
    ## When To Use

    - Unknown binaries, downloaded archives and installers, and repositories you
      do not trust, including their build, test, and install scripts.
    - Checks of what such code does to a machine: files it writes, processes it
      starts, what its display shows (`sbx screenshot`).

    Guests have no network. Fetch inputs on the host into `$TMPDIR` without
    running them, then copy them in.

    ## When Not To Use

    - NixOS configuration tests: use the NixOS test driver
      (`pkgs.testers.runNixOSTest`) or `nixos-rebuild build-vm`.
    - Offline one-shots of an OCI image: use `podman --module untrusted run`.

    ## One-Shot Work

    `sbx run` creates a sandbox, copies inputs in, runs the command, copies
    outputs out, and destroys the sandbox even when a step fails. Prefer it to
    the create/exec/destroy sequence.

    ```bash
    sbx run nixos --in ./repo --out /root/repo/result.txt --to "$TMPDIR" -- make -C repo test
    ```

    - `--in PATH` (repeatable) copies a host path into `/root/` in the guest.
    - `--out GUEST_PATH` (repeatable) needs `--to DIR`, a host directory.
    - Host paths sit under the caller's git checkout, `~/trees`, or `$TMPDIR`; a
      copy out never overwrites an existing target.
    - `--timeout 10m` bounds the command; `--ttl`, `--mem`, and `--cpus` size the
      sandbox within the host ceilings.

    ## Verbs

    | Verb                                         | Effect                                       |
    | -------------------------------------------- | -------------------------------------------- |
    | `run <base> [flags] -- CMD`                  | create, copy in, exec, copy out, destroy     |
    | `create <base> [--name N] [--ttl 30m]`       | start a sandbox and wait for SSH             |
    | `exec <name> [--timeout T] [--agent] -- CMD` | run over SSH; `--agent` uses qemu-ga         |
    | `cp <src> <dst>`                             | one side is `<name>:<path>`; no dst = `xfer` |
    | `destroy <name>` / `--mine` / `--expired`    | stop and delete sandboxes                    |
    | `list [--mine]`, `info <name>`               | state, CID, TTL left, `xfer` directory       |
    | `screenshot <name> [--ocr]`                  | display to PNG in `xfer`, OCR text optional  |
    | `base list`, `base build <base>`             | show or build Nix bases                      |
    | `gc [--dry-run]`                             | remove expired and orphaned sandboxes        |

    `--mine` acts on sandboxes started from the current Claude Code session or
    Codex thread. Destroy what you create once done, or keep `--ttl` short.

    ## JSON Contract

    Pass `--json` to any verb; stdout is then one JSON document.

    - `exec`: `{exit_code, stdout, stderr, truncated, timed_out}`.
    - `run`: `{sandbox, in, exec, out}`, with `exec` shaped as above.
    - `exec` and `run` exit with the guest command's status, 124 after
      `--timeout`.
    - Failures print `{"error": {"code", "message"}}` and exit 1, or 2 for a
      usage error. `base-missing` means `sbx base build <base>` comes first.
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
