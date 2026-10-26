# sbx in the shell

Run `sbx` without arguments to print help and exit successfully.
Help needs no configured base, running daemon, or sandbox.
Use a command's `--help` option for its flags:

```sh
sbx
sbx create --help
sbx share attach --help
```

A command's help shows its usage, one example, and the host's defaults and ceilings for `--mem`, `--cpus`, `--ttl`, and `--wait`.
Those values come from the rendered settings, so help leaves them out where the settings do not load.

## Tab completion

The package installs completion scripts for Bash, Zsh, and Fish in their standard discovery directories.
Open a new shell after rebuilding the system to load them.
Zsh discovers `_sbx` through its completion path; the existing fzf-tab integration displays the candidates.

- Commands, nested commands, options, and enum values follow the CLI parser.
- Base names include configured cloud and Windows bases; `base build` offers Nix bases and `base prepare` offers cloud images.
- Sandbox names come from local state directories, including stopped sandboxes.
- Copy endpoints offer sandbox names with a colon; the other endpoint completes host files.
- Host input files and output directories support path completion, including spaces.
- Share names follow the local grant policy, and key chords retain their modifier prefix.

Completion reads local settings and state without starting libvirt, booting guests, or issuing guest commands.
Guest paths, typed text, and guest arguments after `--` receive no host file or option suggestions.
An incomplete command, including `sbx --json` without a verb, still reports a usage error.
