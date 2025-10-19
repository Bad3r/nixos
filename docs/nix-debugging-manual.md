# Nix Ecosystem Debugging Manual

## 1. Foundational Debugging Principles

Effective debugging in the Nix ecosystem requires a conceptual framework that extends beyond mere command execution. Understanding these foundational principles is the bedrock of all advanced techniques.

### 1.1 The Two Phases of Nix: Evaluation vs. Realisation

At the heart of Nix's design is a strict separation between two distinct phases. Identifying which phase an error occurs in is the most critical first step.

- **Evaluation Phase**: A pure, functional process where Nix language code (`.nix` files) is interpreted to produce a set of `.drv` (derivation) files. These files are the blueprints for builds. This phase is where you encounter language-level problems: syntax errors, undefined variables, type mismatches, or infinite recursion.
- **Realisation (Build) Phase**: An imperative, side-effectful process where the Nix daemon executes a derivation's build script in a sandboxed environment. This is where compilation failures, failed tests, or incorrect file permissions manifest.

An evaluation error (e.g., "undefined variable 'pkgs'") must be diagnosed with language tools like the REPL, not by inspecting build logs, because a build never started. Conversely, a build error (e.g., a C++ compilation failure) must be diagnosed by examining logs (`nix log`) or entering the build environment (`nix-shell`).

### 1.2 Embracing Laziness: Strategies for Forcing Evaluation

Nix is a lazy language, meaning expressions are not evaluated until their results are actually required. This is a frequent source of confusion, as `builtins.trace` statements may not print if the value they are attached to is not used.

To effectively debug, you must force evaluation:

- **In the REPL**: Use the `:p <expression>` command to recursively "print" and fully evaluate a data structure, revealing its complete contents.
- **In Code**: Use `builtins.deepSeq` or the more robust `lib.debug.traceSeq`. `lib.debug.traceSeq traceVal returnVal` forces the complete, recursive evaluation of `traceVal` before printing it, guaranteeing that you see the full data structure, not a set of unevaluated "thunks."

### 1.3 Controlling Verbosity: Essential Command-Line Flags

- `--show-trace`: **For evaluation errors.** Disables stack trace truncation, revealing the full sequence of function calls and file locations that led to the error. **Always use this for language-level debugging.**
- `--print-build-logs` / `-L`: **For realisation errors.** Streams the full, real-time build log to the terminal. Essential for diagnosing compilation failures.
- `--verbose` / `-v`: Increases the verbosity of the Nix tool itself. Can be repeated (e.g., `-vvv`).

## 2. Debugging Nix Language Expressions

### 2.1 The Interactive Inspector: Mastering the `nix repl`

The Nix REPL is the cornerstone of interactive language debugging.

- **Loading Code**: Start with `nix repl` and load files with `:l <path>` or flakes with `:lf .`.
- **Essential Commands**:
     - `:p <expr>`: Strictly (deeply) evaluate and print an expression.
     - `:b <expr>`: Build the derivation the expression evaluates to.
     - `:log <expr>`: After a build, display its logs.
     - `:e <expr>`: Open the source code for the expression (e.g., a package) in your `$EDITOR`.
     - `:show-trace`: Toggle stack traces on/off within the REPL session.

### 2.2 Print-Style Debugging and Breakpoints

- **`builtins.trace "msg" val`**: The basic tool. Prints `msg` and returns `val`. Subject to lazy evaluation.
- **`lib.debug.traceSeq val ret`**: The robust tool. Deeply evaluates and prints `val`, then returns `ret`. Use this to avoid laziness issues with complex data structures.
- **`builtins.break`**: For true interactive debugging. Place `builtins.break val` in your code. When you run a Nix command with the `--debugger` flag, evaluation will pause at that point and drop you into a REPL scoped to that exact location, allowing you to inspect all local variables.

### 2.3 Common Errors and Pitfalls

- **"attribute ‘…’ missing"**: A wrong attrpath or scope. Use the REPL and `builtins.attrNames` to inspect available attributes.
- **"infinite recursion encountered"**: A circular dependency in a `let` block or `rec` set. Use `trace` to follow the chain of dependencies and find the loop.

## 3. Analyzing Derivation Builds

When evaluation succeeds but the build fails, shift focus to the realisation phase.

### 3.1 Post-Mortem Analysis: Reading Build Logs

- **`nix log <derivation-path.drv>`**: The canonical command to retrieve the complete, unabridged log of a failed build attempt. The path to the failed `.drv` is always in the error message.
- **Preserving Failed Builds**: Use `nix build --keep-failed`. This preserves the temporary build directory (e.g., in `/tmp/`) so you can `cd` into it for manual investigation.
- **Aggregating Failures**: Use `nix build --keep-going` during large builds to see all failing derivations instead of halting at the first error.

### 3.2 Interactive Build Debugging with `nix-shell`

This is the most powerful technique for complex build failures.

1. Instead of `nix build`, run `nix-shell <derivation.nix>`. This drops you into an interactive shell with the _exact_ same environment as the builder.
2. All environment variables (`$src`, `$out`, `NIX_CFLAGS_COMPILE`, etc.) are set.
3. The standard build phases are available as shell functions. You can run them manually and in order: `unpackPhase`, `configurePhase`, `buildPhase`, `installPhase`.
4. Inspect the logic of a phase with `type buildPhase`.
5. If a phase fails, you can modify its logic by copying its definition, editing it, and pasting the new version directly into your shell. Rerunning the phase will execute your modified version, allowing for rapid iteration.

### 3.3 Advanced Hooks: Pausing Failed Builds with `breakpointHook`

For non-deterministic or CI build failures, add `pkgs.breakpointHook` to the `nativeBuildInputs` of a derivation. If the build fails, the hook will freeze the build environment and print a `cntr attach` command. Running this command as root will attach you to the namespaces of the failed build process for post-mortem analysis.

## 4. Troubleshooting NixOS Systems

### 4.1 Diagnosing `nixos-rebuild` Failures

- **Verbose Activation**: For activation-phase issues, get a detailed trace of the `switch-to-configuration` script's actions by running: `export STC_DEBUG=1; sudo nixos-rebuild switch`
- **Generation Differences**: To understand what changed between the current system and the one you are trying to build, use `nix store diff-closures /run/current-system ./result`.

### 4.2 Debugging Systemd Services

- **`systemctl status <unit>`**: First command to check a service's state and recent logs.
- **`journalctl -u <unit>`**: View the complete log history for a service.
- **`journalctl -f`**: Follow logs in real-time.
- **`systemctl cat <unit>`**: See the exact unit file NixOS generated.
- **`systemd-analyze blame` / `critical-chain`**: Find slow or hung services during boot.

### 4.3 Investigating Boot and Kernel Issues

The NixOS boot process has two stages. Debugging Stage 1 (the initrd) requires special kernel parameters, added at the boot menu:

- **`rd.systemd.debug_shell`**: Spawns a debug shell on TTY9 (Ctrl+Alt+F9) inside the initrd environment, allowing you to debug issues like LUKS decryption or ZFS pool imports.
- **`boot.shell_on_fail`**: Drops to a root shell on stage-1 failure.
- **`boot.trace`**: Enables `set -x` tracing for all stage-1/2 scripts.

### 4.4 Managing Debug Symbols

By default, Nix packages are stripped. To debug with GDB:

- **Per-Package**: Use `pkgs.enableDebugging <package>` to recompile a single package with full debug info.
- **System-Wide**: Set `environment.enableDebugInfo = true;` in `configuration.nix`.
- **On-Demand (Recommended)**: Use a debuginfod server like `nixseparatedebuginfod`. This allows GDB to automatically download required debug symbols and source files over HTTP as they are needed.

## 5. Debugging Home Manager

### 5.1 Diagnosing Activation and Service Failures

- **Dry Run**: Preview the changes that will be made without touching your home directory: `home-manager switch --dry-run`.
- **Check the Service**: Home Manager uses a user-level systemd instance. Check for activation errors with `journalctl --user -u home-manager-$USER.service`.
- **Custom Activation Scripts**: If you write custom `home.activation` scripts, note that they are passed `DRY_RUN` and `VERBOSE` environment variables, which your scripts should respect.

### 5.2 Inspecting and Iterating on Generated Files

To iterate quickly on a configuration (e.g., for `nvim`), use `config.lib.file.mkOutOfStoreSymlink` to create a symlink that points directly to the source file in your configuration directory. This allows changes to be reflected immediately without needing to run `home-manager switch` until you are done.

## 6. Useful Third-Party Debugging Tools

- **`nix-tree`**: Interactive TUI to browse dependency graphs.
- **`nvd`**: Diffs the contents of two closures to see what files changed.
- **`manix`**: CLI doc/option search across nixpkgs, NixOS, and Home Manager.
- **`nh`**: Ergonomic wrapper for `nixos-rebuild` and `home-manager`.

## 7. Quick Reference

```bash
# --- Language & Evaluation ---
nix repl               # Start REPL, then :? :l :lf :p :b
nix build . --show-trace # Get full error trace on evaluation failure

# --- Build Failures ---
nixos-rebuild switch -L # Stream build logs
nix log /nix/store/<hash>.drv # View logs of a failed build
nix-shell <derivation>   # Enter interactive build shell
nix build --keep-failed  # Preserve failed build directory for inspection

# --- Dependency & Generation Analysis ---
nix why-depends <a> <b> # Explain dependency path
nix store diff-closures <gen1> <gen2> # Show differences between generations

# --- NixOS System ---
systemctl status <unit>
journalctl -u <unit> -b -1 # Logs from previous boot
export STC_DEBUG=1; sudo nixos-rebuild switch # Verbose activation

# --- Boot Flags (add at boot menu) ---
rd.systemd.debug_shell boot.shell_on_fail boot.trace

# --- Home Manager ---
home-manager switch --dry-run # Preview changes
home-manager switch --show-trace -L -v # Verbose build/activation
journalctl --user -fu home-manager-$USER.service
```
