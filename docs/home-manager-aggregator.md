# Home Manager Aggregator (`flake.homeManagerModules`)

This repository exposes Home Manager modules via a dedicated aggregator so they compose exactly like system modules.

## Namespace Layout

| Key                                                        | Type                      | Description                                                          |
| ---------------------------------------------------------- | ------------------------- | -------------------------------------------------------------------- |
| `flake.homeManagerModules.base`                            | Deferred module (merged)  | Bootstrap for every user: shell defaults, CLI tools, shared options. |
| `flake.homeManagerModules.gui`                             | Deferred module (merged)  | Desktop integrations pulled into graphical hosts.                    |
| `flake.homeManagerModules.apps.<name>`                     | Deferred module (per key) | Individual applications (CLI or GUI) addressed by name.              |
| `flake.homeManagerModules.r2Secrets`, `context7Secrets`, … | Deferred modules          | Optional helpers that wire sops-managed material when present.       |

Modules register into these keys exactly once. Because flake-parts merges by attribute name, multiple files can extend `base`/`gui` safely:

```nix
# modules/files/fzf.nix
_: {
  flake.homeManagerModules.base = { pkgs, ... }: {
    programs.fzf.enable = true;
  };
}

# modules/messaging-apps/discord.nix
_: {
  flake.homeManagerModules.gui = { pkgs, ... }: {
    home.packages = [ pkgs.discord ];
  };
}
```

Per-app modules live under `apps.<name>` and **must** be functions:

```nix
# modules/apps/kitty.nix
_: {
  flake.homeManagerModules.apps.kitty = { pkgs, ... }: {
    programs.kitty.enable = true;
  };
}
```

## Default App Imports

The glue layer in `modules/home-manager/nixos.nix` imports a shared list of app modules directly from `flake.homeManagerModules.apps`. Each name is resolved via guarded lookups so evaluation fails fast when an expected app is missing:

```nix
hmApps = config.flake.homeManagerModules.apps or { };
hasApp = name: lib.hasAttr name hmApps;
getApp = name:
  if hasApp name then lib.getAttr name hmApps
  else throw "Unknown Home Manager app '${name}' referenced by base imports";
defaultAppImports = [
  "codex"
  "bat"
  "eza"
  "fzf"
  "kitty"
  "alacritty"
  "wezterm"
];
```

Hosts that need additional Home Manager apps can append to the import list manually or create their own helper modules. Update `defaultAppImports` when you want the baseline profile to carry another app by default.

## Authoring Rules

1. **Always export a module value** – avoid `flake.homeManagerModules.base.home.sessionVariables = …;` style dot assignments.
2. **Guard optional modules** – if an app depends on a secret or package, check for availability in the module body.
3. **Keep names stable** – the key under `apps.<name>` is what the glue layer references. Prefer lowercase hyphen-less identifiers (`kitty`, `wezterm`, `codex`).
4. **Document secrets** – when an app needs credentials, reference `docs/sops-nixos.md` so readers know how to provide them.

## Validation

- `nix fmt`
- `nix develop -c pre-commit run --all-files`
- `nix flake check --accept-flake-config`

When you change the default app list in `modules/home-manager/nixos.nix`, rerun the checks above. Any missing app reference still throws during evaluation because of the guarded lookup.
