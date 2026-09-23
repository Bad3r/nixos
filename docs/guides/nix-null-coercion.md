# Debugging Nix null coercion errors

Nix reports `cannot coerce null to a string` when evaluation uses `null` where an option or interpolation requires a string.
The failure can surface during final validation of a merged module configuration, after earlier evaluation appears to succeed.

## Read the trace

Rerun the failing command with `--show-trace` and follow the first project-owned frame above the module-system frames.
A representative failure ends with the merged configuration validation:

```text
error: cannot coerce null to a string: null

... while checking flake output 'nixosConfigurations'
... while checking the NixOS configuration
... while calling the 'seq' builtin
  at nixpkgs/lib/modules.nix
```

Check the option declaration and every definition contributing to the value named by that frame.
An option typed as a string cannot accept a conditional branch or default that evaluates to `null`.

## Isolate the source

Common causes include:

- Reading `config` in a binding that must be evaluated before the corresponding option definitions exist.
- Depending on a required option that no imported module defines.
- Supplying `null` as a default for a non-null option type.
- Reading `config.flake.*` from the inner NixOS or Home Manager module context.
- Reading `config.home.*` or `config.services.*` from the outer flake-parts context.

Bisect imported modules when the trace ends in generic module-system code:

1. Disable half of the candidate imports.
2. Evaluate the same target again.
3. Keep the half that still reproduces the failure.
4. Repeat until one module or definition remains.

Use `builtins.trace` on the suspected value before adding a fallback:

```nix
username = builtins.trace "owner username: ${builtins.toJSON config.flake.lib.meta.owner.username}"
  config.flake.lib.meta.owner.username;
```

An `or` fallback can hide a missing required definition.
Add one only when the attribute is optional by contract.

## Repair the definition

- Move premature `config` access into the deferred `config` block.
- Use `lib.mkIf` or `lib.mkMerge` when a definition depends on another option.
- Pass cross-context values through `specialArgs`, `_module.args`, or an explicit module argument.
- Give required options non-null defaults or define them in every importing configuration.
- Confirm the outer and inner module contexts against [module authoring](../architecture/02-module-authoring.md).

Re-evaluate the smallest failing target before running the wider flake check.
