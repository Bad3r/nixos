## Code examples and other commands

In free text names and complete invocations of other commands (e.g. `ssh` or `tar -xvf src.tar`) should be marked with `Ic`, fragments of command lines should be marked with `Ql`.

Larger code blocks or those that cannot be shown inline should use indented literal display block markup for their contents, i.e.

```programlisting
.Bd -literal -offset indent
...
.Ed
```

Contents of code blocks may be marked up further, e.g. if they refer to arguments that will be substituted into them:

```programlisting
.Bd -literal -offset indent
{
  config.networking.hostname = "\c
.Ar hostname Ns \c
";
}
.Ed
```

---

|     |     |                                    |
| :-- | :-: | ---------------------------------: |
|     |     |               [Next](options.html) |
|     |     |  Appendix A. Configuration Options |
