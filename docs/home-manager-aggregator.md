# Home Manager Aggregator (`flake.homeManagerModules`)

This repository exposes Home Manager modules via a dedicated aggregator that assembles a curated set of modules for the single `vx@system76` environment. Instead of depending on dynamic registry state, the aggregator imports the source files directly and extracts the Home Manager fragments they export. For the bigger picture (system aggregators, host layout, tooling), see `docs/configuration-architecture.md`.

## Namespace Layout

| Key                                                        | Type                      | Description                                                                       |
| ---------------------------------------------------------- | ------------------------- | --------------------------------------------------------------------------------- |
| `flake.homeManagerModules.base`                            | Deferred module           | Bootstrap module exported by a source file (for example `home-manager/base.nix`). |
| `flake.homeManagerModules.gui`                             | Deferred module           | GUI-specific helpers (for example Stylix desktop tweaks).                         |
| `flake.homeManagerModules.apps.<name>`                     | Deferred module (per key) | Individual application modules under `modules/hm-apps/<name>.nix`.                |
| `flake.homeManagerModules.r2Secrets`, `context7Secrets`, … | Deferred modules          | Optional helpers that wire SOPS-managed material when present.                    |

Each contributor module still exports into these attribute paths, but the aggregator now reads them explicitly with `lib.attrByPath` when constructing the import list. Multiple files can extend `base`/`gui` safely—the loader extracts the value after evaluation.

```nix
# modules/files/fzf.nix
_: {
  flake.homeManagerModules.base = { pkgs, ... }: {
    programs.fzf.enable = true;
  };
}

# modules/terminal/alacritty.nix
_: {
  flake.homeManagerModules.gui = _: {
    programs.alacritty.enable = true;
  };
}
```

Per-app modules live under `apps.<name>` and **must** be functions:

```nix
# modules/hm-apps/kitty.nix
_: {
  flake.homeManagerModules.apps.kitty = _: {
    programs.kitty.enable = true;
  };
}
```

## Default App Imports

The glue layer in `modules/home-manager/nixos.nix` keeps a curated list of default apps, imports each file from `modules/hm-apps/<name>.nix`, and extracts the exported module with a guarded lookup. Evaluation still fails fast when an expected app is missing:

```nix
loadAppModule = name:
  let
    filePath = ../hm-apps + "/${name}.nix";
  in
  if builtins.pathExists filePath then
    loadHomeModule filePath [ "flake" "homeManagerModules" "apps" name ]
  else
    throw ("Home Manager app module file not found: " + toString filePath);

defaultAppImports = [
  "codex"
  "bat"
  "eza"
  "fzf"
  "ghq-mirror"
  "kitty"
  "alacritty"
  "wezterm"
];

appModules = map loadAppModule (lib.unique (defaultAppImports ++ extraAppImports));
```

Hosts can still append to `home-manager.extraAppImports` to load more modules; the loader will resolve the files the same way.

## Authoring Rules

1. **Always export a module value** – export under `flake.homeManagerModules.*` so the loader can pick it up.
2. **Guard optional modules** – if an app depends on a secret or package, check for availability in the module body.
3. **Keep names stable** – the key under `apps.<name>` must match the filename (`kitty`, `wezterm`, `codex`) so the loader finds the module.
4. **Document secrets** – when an app needs credentials, reference `docs/sops/README.md` so readers know how to provide them.

## Validation

- `nix fmt`
- `nix develop -c pre-commit run --all-files`
- `nix flake check --accept-flake-config`

When you change the default app list in `modules/home-manager/nixos.nix`, rerun the checks above. Any missing app reference still throws during evaluation because of the guarded lookup.
