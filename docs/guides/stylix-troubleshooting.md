# Stylix troubleshooting

Most Stylix failures come from a target set in the wrong context or an enable that overrides `autoEnable`.

## Common Pitfalls

### Pitfall 1: Setting HM Targets in NixOS Modules

```nix
# WRONG -- dunst target only exists in Home Manager
flake.nixosModules.apps.dunst = { ... }: {
  stylix.targets.dunst.enable = lib.mkDefault true;  # ERROR: undefined option
};
```

This causes evaluation errors unless `_module.check = false` is set, which masks the problem.

### Pitfall 2: Redundant Target Enables

```nix
# WRONG -- redundant and potentially buggy
flake.homeManagerModules.apps.fzf = { lib, ... }: {
  programs.fzf.enable = true;
  stylix.targets.fzf.enable = lib.mkDefault true;  # Redundant!
};
```

Stylix already enables this automatically.
The `lib.mkDefault` can override user's `stylix.autoEnable = false`.

### Pitfall 3: Using \_module.check = false

Never use `_module.check = false` to silence option errors.
This masks real problems:

```nix
# WRONG -- hides undefined option errors
configurations.nixos.myhost.module = {
  _module.check = false;  # Don't do this
  imports = [ ... ];
};
```

Instead, fix the root cause by ensuring options are only set in their valid context.

## Debugging Stylix Issues

### Check Which Targets Exist

```bash
# List NixOS stylix targets
nix eval .#nixosConfigurations.songbird.options.stylix.targets \
  --apply builtins.attrNames 2>/dev/null | tr ',' '\n' | tr -d '[]" '
```

### Verify Target State

```bash
# Check if a specific target is enabled in the final config
nix eval .#nixosConfigurations.songbird.config.stylix.targets.console.enable
```

### Trace autoEnable Behavior

If theming isn't applying, verify:

1. `stylix.autoEnable` is `true` (or not explicitly `false`)
2. The corresponding `programs.<app>.enable` is `true`
3. The target exists in the current context (NixOS vs HM)

## Related

- [Stylix Integration](stylix-integration.md)
