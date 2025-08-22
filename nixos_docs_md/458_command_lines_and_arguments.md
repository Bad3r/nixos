## Command lines and arguments

In any manpage, commands, flags and arguments to the _current_ executable should be marked according to their semantics. Commands, flags and arguments passed to _other_ executables should not be marked like this and should instead be considered as code examples and marked with `Ql`.

- Use `Fl` to mark flag arguments, `Ar` for their arguments.

- Repeating arguments should be marked by adding an ellipsis (spelled with periods, `...`).

- Use `Cm` to mark literal string arguments, e.g. the `boot` command argument passed to `nixos-rebuild`.

- Optional flags or arguments should be marked with `Op`. This includes optional repeating arguments.

- Required flags or arguments should not be marked.

- Mutually exclusive groups of arguments should be enclosed in curly brackets, preferably created with `Bro`/`Brc` blocks.

When an argument is used in an example it should be marked up with `Ar` again to differentiate it from a constant. For example, a command with a `--host name` option that calls ssh to retrieve the host’s local time would signify this thusly:

```programlisting
This will run
.Ic ssh Ar name Ic time
to retrieve the remote time.
```
