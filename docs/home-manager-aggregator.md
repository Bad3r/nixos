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

## Roles as Data

Role membership is stored as pure data in `flake.lib.homeManager.roles` (`modules/meta/hm-roles.nix`). Example:

```nix
flake.lib.homeManager.roles = {
  cli = [ "codex" "bat" "eza" "fzf" ];
  terminals = [ "kitty" "alacritty" "wezterm" ];
};
```

The glue layer in `modules/home-manager/nixos.nix` resolves those app names using guarded lookups:

```nix
hasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.homeManagerModules;
getApp = name:
  if hasApp name then lib.getAttrFromPath [ "apps" name ] config.flake.homeManagerModules
  else throw "Unknown Home Manager app '${name}' referenced by roles";
roleToModules = roleName: map getApp (roles.${roleName} or [ ]);
```

Each user import list starts with base modules (`inputs.sops-nix.homeManagerModules.sops`, state-version glue, `base`, secrets helpers) and then appends `roleToModules "cli"` and `roleToModules "terminals"`. Extend roles by editing `modules/meta/hm-roles.nix`; no code changes required.

## Authoring Rules

1. **Always export a module value** – avoid `flake.homeManagerModules.base.home.sessionVariables = …;` style dot assignments.
2. **Guard optional modules** – if an app depends on a secret or package, check for availability in the module body.
3. **Keep names stable** – the key under `apps.<name>` is the lookup string used by roles. Prefer lowercase hyphen-less identifiers (`kitty`, `wezterm`, `codex`).
4. **Document secrets** – when an app needs credentials, reference `docs/sops-nixos.md` so readers know how to provide them.

## Validation

- `nix fmt`
- `nix develop -c pre-commit run --all-files`
- `nix flake check --accept-flake-config`

If you add a new role or change role membership, update `modules/meta/hm-roles.nix` and rerun the checks above. Any missing app reference throws during evaluation because of the guarded lookup.
