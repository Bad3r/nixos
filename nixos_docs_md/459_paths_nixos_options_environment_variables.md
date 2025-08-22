## Paths, NixOS options, environment variables

Constant paths should be marked with `Pa`, NixOS options with `Va`, and environment variables with `Ev`.

Generated paths, e.g. `result/bin/run-hostname-vm` (where `hostname` is a variable or arguments) should be marked as `Ql` inline literals with their variable components marked appropriately.

- When `hostname` refers to an argument, it becomes `.Ql result/bin/run- Ns Ar hostname Ns -vm`

- When `hostname` refers to a variable, it becomes `.Ql result/bin/run- Ns Va hostname Ns -vm`
