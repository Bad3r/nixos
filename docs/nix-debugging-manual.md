# Nix Ecosystem Debugging Manual

## 1. Introduction

Debugging in the Nix ecosystem spans expression evaluation, reproducible builds, and declarative user environments. This manual summarizes practical techniques drawn from official manuals, community knowledge, and established tooling so you can triage issues systematically across Nix, NixOS, and Home Manager.citeturn15search0

---

## 2. Debugging Nix Language Expressions

### 2.1 Using the Nix REPL (`nix repl`)

- Launch `nix repl` with flake or file inputs and inspect bindings via `:?`, `:doc`, and `:type` for quick reference while iterating on expressions.citeturn6search1
- Toggle stack traces interactively with `:show-trace` or collect build logs with `:log <derivation>` to pinpoint failing derivations without leaving the REPL.citeturn6search1
- Use `:b drv` or `:bl` to build derivations in place, creating GC roots that preserve artifacts for deeper inspection.citeturn6search1
- Combine `--expr` or `--file` with `--extra-experimental-features 'flakes repl-flake'` when testing flake-based inputs so the REPL mirrors production evaluation settings.citeturn6search1

```bash
nix repl --expr 'import <nixpkgs> {}'
nix-repl> :doc builtins.map
nix-repl> :show-trace
```

### 2.2 Tracing Evaluation (`builtins.trace`)

- `builtins.trace "message" value` emits diagnostics while returning `value`, and `builtins.traceVerbose` obeys the `trace-verbose` setting to silence noisy traces in normal runs.citeturn16search2
- Enable `builtins.break` with `--debugger` and `:bt`/`:st` commands to step through evaluation paths when the standard trace output is insufficient.citeturn16search2
- Prefer library helpers such as `lib.debug.traceVal`, `traceValFn`, and `traceSeq` to force deeper evaluation or format values without rewriting existing expressions.citeturn15search0
- For performance investigations, set `trace-function-calls = true` in `nix.conf` to emit function timings, or `trace-import-from-derivation = true` to spot unintentional IFD usage during evaluation.citeturn16search3turn16search4

```nix
{ lib, ... }:

let
  traced = lib.debug.traceValFn (v: "expanding ${v}") (builtins.trace "enter" 42);
in traced
```

### 2.3 Common Errors and Pitfalls

- Infinite recursion typically arises when option definitions depend on themselves; convert conditionals into `lib.mkIf` or restructure module arguments to break cycles.citeturn1search0
- Missing attributes and type mismatches surface clearer diagnostics when rerun with `--show-trace`, which expands stack frames to the originating file and option definition.citeturn16search2
- Avoid accessing `pkgs.lib` inside module arguments—import `lib` explicitly to prevent recursion through package set initialization.citeturn1search0

### 2.4 Language-Level Debugging Tools (e.g., `nix-debug`, `nix-tree`)

- Use `nix eval --show-trace --expr '<expr>'` or `nix-instantiate --eval --strict` to surface evaluation errors without building derivations.citeturn6search2
- Explore dependency graphs with `nix-tree <installable>` or `nix path-info --recursive --closure-size` to identify unexpectedly large closures and hidden references.citeturn19view0turn7search0
- Compare two derivations using `nix store diff-closures /path/or/flake1 /path/or/flake2` to detect runtime-impacting differences between generations.citeturn7search2
- Analyze why a package depends on another via `nix why-depends` to trace a single chain of references through the store.citeturn7search1
- For ad hoc profiling, combine `nix build --keep-failed` with standard Unix tools inside the retained build directory, then refresh caches using `nix log` to review build output.citeturn6search0

---

## 3. Debugging NixOS Systems

### 3.1 Analyzing Build Failures

- When `nixos-rebuild` aborts, inspect failures immediately with `nix log <installable>`; add `--print-build-logs` or `-L` to stream logs during the rebuild.citeturn6search0
- Preserve failed build environments with `nix build --keep-failed` or `nix-build --keep-failed` so you can drop into `result-tmp` directories for manual investigation.citeturn6search0
- Detect nondeterministic outputs by pairing `--check` with `nix store diff-closures` or the `.check` outputs generated after a mismatch.citeturn7search2
- Use `nix build --keep-going` during large upgrades to aggregate all failing derivations instead of halting at the first error.citeturn6search0

### 3.2 Debugging Systemd Services

- Query unit health with `systemctl status <unit>` and follow live logs via `journalctl -fu <unit>` or boot-scoped summaries with `journalctl -b`.citeturn2search0
- On configuration switches, enable verbose activation by exporting `STC_DEBUG=1` before running `sudo nixos-rebuild switch` to view each action performed by `switch-to-configuration`.citeturn2search0
- For crash loops, combine `systemctl reset-failed <unit>` with targeted restarts so journal output reflects a single activation attempt without historic noise.citeturn2search0
- Use `nixos-option services.<name>.<option>` to verify the rendered option tree matches expectations before restarting daemons.citeturn4search1

### 3.3 NixOS Debugging Options

- Apply boot-time flags such as `boot.shell_on_fail`, `boot.trace`, or `systemd.log_level=debug` from the GRUB editor to access emergency shells and high-verbosity journals when early boot fails.citeturn4search2
- Enable the NixOS test driver’s SSH backdoor or interactive mode when reproducing flaky module tests to inspect the virtual machine state directly.citeturn4search2
- Configure kernel builds with debug symbols (e.g., `linuxKernel.kernels.<version>.extraConfig = "KGDB y";`) to attach kernel debuggers in low-level investigations.citeturn4search2

### 3.4 Inspecting the Nix Store and Derivations

- Use `nix path-info --recursive --closure-size /run/current-system` to quantify deployed closure size and locate unexpectedly large dependencies.citeturn7search0
- Trace dependency chains with `nix why-depends <a> <b>` to justify closures or detect hidden references.citeturn7search1
- Verify binary provenance by reading store logs (`nix log <installable>`) or listing remote cache metadata with `nix store ls --store https://cache.nixos.org --long <path>`.citeturn6search0turn6search6

---

## 4. Debugging Home Manager

### 4.1 Activation Issues

- Run `home-manager switch --show-trace` to expand evaluation backtraces for option type or dependency errors before activation aborts.citeturn10view0
- Inspect the systemd user unit with `systemctl --user status home-manager-$USER.service` and stream logs via `journalctl --user -fu home-manager-$USER.service` on NixOS installations that manage activation as a service.citeturn10view0
- Use `home-manager switch --dry-run` (or `--activation-trace`) to preview file links without touching the live home directory, then rerun with `--show-trace` if validation fails.citeturn10view0

```bash
home-manager switch --show-trace
systemctl --user status "home-manager-$USER.service"
journalctl --user -fu "home-manager-$USER.service"
```

### 4.2 Inspecting Generated Files

- Build without activating using `home-manager build` and inspect the `result` symlink for rendered dotfiles under `result/home-files` or scripts via `result/activate`.citeturn10view0
- Diff generations with `home-manager generations` followed by `nix store diff-closures $oldGen $newGen` to understand configuration drift before promoting an update.citeturn10view0turn7search2
- When conflicts arise (e.g., existing files), the activation check lists blocking paths; resolve by moving or adopting them into `home.file.*.source`.citeturn10view0

### 4.3 Debugging Modules

- Refer to `man home-configuration.nix` or `home-manager help option <name>` to confirm option types, defaults, and merged definitions prior to editing module code.citeturn8search5
- Custom activation scripts defined under `home.activation.*` should respect `DRY_RUN` and can emit verbose output by checking the `VERBOSE` environment variable set during activation.citeturn11view0
- Use `home-manager --override-input` or `--flake` overrides to test module patches against alternate Home Manager revisions without disturbing the system profile.citeturn10view0

---

## 5. Useful Third-Party Debugging Tools

- `nix-tree`: curses UI for exploring dependency trees, ideal for spotting unexpected runtime references.citeturn19view0
- `nh`: wrapper around common `nixos-rebuild` and `nix` invocations that surfaces switch failures and generation history with readable output.citeturn18search2
- `nvd`: compare Nix store closures or generations to highlight file-level differences after rebuilds, helping confirm whether a change affects runtime artifacts.citeturn18search2

---

## 6. Conclusion

By combining REPL-driven diagnostics, structured logging, and store-level introspection, you can shorten feedback loops across Nix expressions, NixOS hosts, and Home Manager environments. Build a personal toolkit from the commands and utilities above, automate recurring checks (e.g., `nix log`, `nix store diff-closures`), and lean on verbose activation modes to keep declarative configurations reliable.citeturn15search0
