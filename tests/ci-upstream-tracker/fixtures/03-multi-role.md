### Type

refactor

### Scope

envfs

### Summary

All four roles (blocker / fix / related / superseded) appear across the
three URL fields. No upstream has resolved yet.

### Unblock condition

Unblocked when every blocker resolves.

### Upstream pull requests

blocker https://github.com/NixOS/nixpkgs/pull/500707 - r-ryantm envfs bump
fix https://github.com/Mic92/envfs/pull/216 - wait until filesystem is ready
superseded https://github.com/NixOS/nixpkgs/pull/449551 - original attempt

### Upstream issues

related https://github.com/Mic92/envfs/issues/206 - mount protocol warning

### Upstream releases and channels

fix https://github.com/Mic92/envfs/releases/tag/1.2.0 - envfs >= 1.2.0

### Local workaround / affected code

modules/base/envfs.nix

### Exit criteria

- [ ] every blocker resolved

### Validation

### Notes

### Confirmations

- [x] placeholder
