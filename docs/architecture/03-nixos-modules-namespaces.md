# flake.lib and flake.csec Namespaces

`flake.lib` holds pure helper data and small utilities, and `flake.csec` holds cybersecurity-tooling NixOS modules.
Both sit beside the `flake.nixosModules` aggregator described in [NixOS Modules](03-nixos-modules.md).

## `flake.lib` Namespaces

`modules/meta/flake-output.nix` declares each sub-namespace with its type and description, and individual modules populate them.
`nixosBrowsers` is the exception, a freeform entry that `modules/meta/nixos-browser-helpers.nix` publishes.

- `flake.lib.meta`: repo metadata, such as owner identity and input branch pins, and the source of the `metaOwner` argument.
- `flake.lib.nixos`: app-registry helpers such as `hasApp` and `getApp`, and host-conditional flags under `hosts.<name>`.
- `flake.lib.hostApps`: the `mk` builder that turns a host's rows into its `programs` and `services` overrides.
- `flake.lib.nixosBrowsers`: browser-registry helpers such as `hasBrowser` and `getBrowser` for `modules/browsers/`.
- `flake.lib.homeManager`: helpers and metadata used by Home Manager modules.
- `flake.lib.security`: shared SOPS helpers, such as `sopsInstallSecretsService`.
- `flake.lib.nixvim`: helpers for NixVim integrations and the shared module shape.
- `flake.lib.xdg`: desktop file mappings and MIME helpers, consumed by `modules/meta/ci.nix`.
- `flake.lib.agents`: the registry and compiled outputs for MCP servers and skills, from `modules/agents/*.nix`.
- `flake.lib.checks`: lightweight evaluation-only checks that build no derivations.

Helpers stay pure and idempotent; anything that needs heavy evaluation belongs in a module rather than a `flake.lib.*` entry.

## The `flake.csec` Namespace

Cybersecurity-tooling NixOS modules register under `flake.csec.<feature>`, declared in `modules/meta/flake-output.nix` as `attrsOf deferredModule`.
Each feature is a first-class entry, because sub-keys under `flake.nixosModules.*` (`lazyAttrsOf raw`) give no per-feature merge semantics without flat name mangling.

```nix
flake.csec = {
  wordlists = { ... };  # Kali-style symlinks under /usr/share/wordlists/
};
```

The common host aggregate imports each feature module and enables it for every `shareCommon` host:

```nix
# modules/hosts/common/imports.nix
flake.nixosModules.hosts-common.imports = [
  config.flake.csec.wordlists
  # ...
  { csec.wordlists.enable = true; }
];
```

`modules/csec/wordlists.nix` exports `flake.csec.wordlists`, Kali-style wordlist symlinks populated at activation from `pkgs.wordlists` and app-owned manual links.
