# NixOS Configuration Review Checklist

This checklist provides a systematic approach to reviewing and evaluating the current NixOS configuration using the Dendritic Pattern.

## Prerequisites

- [ ] Enter development shell: `nix develop`
- [ ] Ensure working directory is `/home/vx/nixos`
- [ ] Check current host: `hostname` (should be `system76`)
- [ ] Note current generation: `generation-manager current`

## 1. Code Quality & Compliance

### Pre-commit Validation

- [ ] Run all pre-commit hooks: `nix develop -c pre-commit run --all-files`
  - [ ] All nixfmt-rfc-style checks pass
  - [ ] All deadnix checks pass (no dead code)
  - [ ] All statix checks pass (no anti-patterns)
  - [ ] All flake-checker checks pass
  - [ ] All shellcheck checks pass
  - [ ] No typos detected
  - [ ] No trailing whitespace
  - [ ] No private keys detected
  - [ ] No secrets detected (ripsecrets)
  - [ ] YAML files valid
  - [ ] JSON files valid

### Dendritic Pattern Compliance

- [ ] Check compliance score: `generation-manager score`
  - [ ] Score is 100/100
  - [ ] No literal path imports (20 points)
  - [ ] input-branches module exists (10 points)
  - [ ] generation-manager tool exists (10 points)
  - [ ] Module headers complete (20 points)
  - [ ] No TODOs remaining (10 points)
  - [ ] nvidia-gpu has specialisation (15 points)
  - [ ] Metadata properly configured (15 points)

### Flake Validation

- [ ] Validate flake structure: `nix flake check --accept-flake-config`
- [ ] Review flake outputs: `nix flake show`
- [ ] Check for warnings in build: `nix build --show-trace .#nixosConfigurations.$(hostname).config.system.build.toplevel 2>&1 | grep -i warn`

## 2. Module Structure Review

### Namespace Hierarchy

- [ ] Verify namespace chain: base → pc → workstation
- [ ] Check base modules: `ls modules/base/`
  - [ ] Console configuration exists
  - [ ] Hardware scanning configured
  - [ ] Nix settings present
  - [ ] User configuration exists
- [ ] Check pc modules: `ls modules/pc/`
  - [ ] Desktop utilities configured
  - [ ] Unfree packages listed
  - [ ] Printing support configured
- [ ] Check workstation modules (if applicable)
  - [ ] Development tools configured
  - [ ] Language support enabled

### Module Organization

- [ ] No files starting with `_` in active modules: `find modules -name "_*" -type f`
- [ ] All modules follow function pattern for pkgs access
- [ ] No module headers (comments at top)
- [ ] All modules use namespace pattern correctly

## 2.5. Home-Manager Configuration Review

### User Environment

- [ ] Check home-manager integration: `cat modules/home-manager-setup.nix`
- [ ] Verify user packages: `grep -r "home.packages" modules/home/ 2>/dev/null || echo "No home packages configured"`
- [ ] Review shell configuration: `ls modules/home/shell/ 2>/dev/null || echo "No shell config directory"`
  - [ ] Shell aliases defined appropriately
  - [ ] Environment variables set correctly
  - [ ] Shell prompt configured

### Home Services

- [ ] Check enabled home services: `grep -r "programs\.\|services\." modules/home/ 2>/dev/null | grep "enable = true" | head -20`
- [ ] Review dotfile management: `grep -r "home.file\." modules/home/ 2>/dev/null | head -10`
- [ ] Verify XDG directories: `grep -r "xdg\." modules/home/ 2>/dev/null | head -10`
- [ ] Check home.stateVersion: `grep -r "home.stateVersion" modules/`

### User-specific Applications

- [ ] Terminal configuration: `grep -r "alacritty\|kitty\|wezterm\|cosmic-term" modules/ | head -10`
- [ ] Editor configuration: `grep -r "vim\|neovim\|emacs\|nixvim" modules/ | head -10`
- [ ] Git user configuration: `grep -r "programs.git\|userName\|userEmail" modules/ | head -10`
- [ ] Browser extensions and settings: `grep -r "programs.firefox\|programs.chromium" modules/home/ 2>/dev/null`

## 3. Host Configuration Review

### System76 Host (if applicable)

- [ ] Review boot configuration: `cat modules/system76/boot.nix`
  - [ ] LUKS encryption configured
  - [ ] Btrfs filesystem settings correct
  - [ ] Boot loader configured properly
- [ ] Check NVIDIA GPU support: `cat modules/system76/nvidia-gpu.nix`
  - [ ] Driver version appropriate
  - [ ] Power management configured
- [ ] Verify network settings: `cat modules/system76/network.nix`
  - [ ] Hostname correct
  - [ ] Network interfaces configured
- [ ] Check for overlays: `grep -r "nixpkgs.overlays" modules/system76/`
- [ ] Verify system.stateVersion: `grep "system.stateVersion" modules/system76/*.nix`



### Common Host Settings

- [ ] SSH configuration secure: `grep -r "openssh" modules/*/ssh.nix`
- [ ] User configuration correct: `cat modules/meta/owner.nix`
  - [ ] Username: `vx`
  - [ ] Email configured
  - [ ] SSH keys present

## 4. Security Audit

### Secrets Management

- [ ] Check for exposed secrets: `nix develop -c pre-commit run ripsecrets --all-files`
- [ ] Review secrets module: `cat modules/security/secrets.nix`
- [ ] Verify GPG configuration: `cat modules/security/gnupg.nix`

### Access Control

- [ ] Review sudo configuration: `cat modules/pc/sudo.nix`
- [ ] Check polkit rules: `cat modules/security/polkit.nix`
- [ ] Verify SSH hardening:
  - [ ] Check PermitRootLogin: `grep -r "PermitRootLogin" modules/ --include="*.nix" | grep -v "#"`
    - Should be set to `"no"` or not present (defaults to no)
  - [ ] Check PasswordAuthentication: `grep -r "PasswordAuthentication" modules/ --include="*.nix" | grep -v "#"`
    - Should be set to `false` or not present (defaults to false)
- [ ] Check password policies:
  - [ ] No plaintext passwords: `grep -r 'password = "' modules/ --include="*.nix" | grep -v "#"`
  - [ ] Review hashed passwords: `grep -r "hashedPassword\|initialPassword" modules/ --include="*.nix" | grep -v "#"`
  - [ ] Verify password files excluded from git: `cat .gitignore | grep -i password`

### Firewall & Networking

- [ ] Review firewall rules: `grep -r "firewall" modules/networking/`
- [ ] Check open ports: `grep -r "openFirewall\|allowedTCPPorts\|allowedUDPPorts" modules/`
- [ ] Verify VPN configuration if present: `cat modules/networking/vpn.nix`

## 5. Services & Applications

### System Services

- [ ] List enabled services: `grep -r "\.enable = true" modules/ | cut -d: -f1 | sort -u | head -20`
- [ ] Review service configurations: `grep -r "services\." modules/ | cut -d: -f1 | sort -u | head -20`
- [ ] Review critical services:
  - [ ] Audio (pipewire): `cat modules/audio/pipewire.nix`
  - [ ] Display (KDE Plasma): `cat modules/window-manager/plasma.nix`
  - [ ] Docker if needed: `cat modules/virtualization/docker.nix`

### Installed Applications

- [ ] Review browser configuration: `ls modules/web-browsers/`
- [ ] Check development tools: `ls modules/development/`
- [ ] Verify messaging apps: `ls modules/messaging-apps/`
- [ ] Review unfree packages: `grep -r "allowedUnfreePackages" modules/`

## 6. Performance & Optimization

### Boot Performance

- [ ] Review boot settings: `cat modules/boot/compression.nix`
- [ ] Check boot visuals: `cat modules/boot/visuals.nix`
- [ ] Verify storage optimization: `cat modules/boot/storage.nix`

### Storage Management

- [ ] Check swap configuration: `cat modules/storage/swap.nix`
- [ ] Review tmp settings: `cat modules/storage/tmp.nix`
- [ ] Verify redundancy if configured: `cat modules/storage/redundancy.nix`

### Nix Store

- [ ] Check filesystem usage: `df -h /nix`
- [ ] Check reclaimable space: `nix-store --gc --print-dead 2>/dev/null | wc -c | numfmt --to=iec`
- [ ] List generation count: `generation-manager list | wc -l`
- [ ] Verify garbage collection works: `DRY_RUN=true generation-manager gc`

## 7. Dependencies & Updates

### Flake Inputs

- [ ] Review all inputs: `nix flake metadata --json | jq '.locks.nodes | keys'`
- [ ] Check input ages: `nix flake metadata --json | jq -r '.locks.nodes | to_entries[] | "\(.key): \(.value.locked.lastModified // "N/A")"' | head -20`
- [ ] Show current lock state: `nix flake metadata`
- [ ] Verify critical inputs:
  - [ ] nixpkgs channel (should be unstable)
  - [ ] home-manager version
  - [ ] flake-parts version

### Package Versions

- [ ] View system packages: `ls -la /run/current-system/sw/bin/ | head -20`
- [ ] Check system dependency tree: `nix-store -q --tree /run/current-system | head -100`
- [ ] Review explicitly configured packages: `grep -r "systemPackages\|environment.packages" modules/ | head -20`
- [ ] Check for security updates: Review nixpkgs commits since last update

## 8. Build & Deployment

### Dry Run Build

- [ ] Test build for current host: `nixos-rebuild build --flake .#$(hostname)`
- [ ] Check build time: Note how long the build takes
- [ ] Review build output for warnings

### Generation Management

- [ ] Current generation stable: No issues in current use
- [ ] Rollback tested: Know how to rollback if needed
- [ ] Cleanup plan: `generation-manager clean 5` keeps last 5 generations

## 9. Documentation Review

### Configuration Documentation

- [ ] CLAUDE.md accurate and up-to-date
- [ ] Module purposes clear from directory names
- [ ] Critical settings documented inline where needed

### Recovery Procedures

- [ ] Recovery guide exists: `ls docs/RECOVERY_GUIDE.md`
- [ ] Boot configuration documented: `ls docs/BOOT_CONFIGURATION_REFERENCE.md`
- [ ] Rollback procedure known

## 10. Final Validation

### Complete System Check

- [ ] Run comprehensive validation:
  ```bash
  # All checks in sequence
  nix develop -c pre-commit run --all-files && \
  generation-manager score && \
  nix flake check --accept-flake-config && \
  nixos-rebuild build --flake .#$(hostname)
  ```

### Test in Safe Mode (Optional)

- [ ] Build without switching: `./build.sh --dry-run` (if supported)
- [ ] Or use: `nixos-rebuild build --flake .#$(hostname)`
- [ ] Review what would change: `nix-diff $(readlink /run/current-system) result`

## 11. NixOS Configuration Best Practices

### Configuration Patterns

- [ ] No hardcoded passwords or secrets in configuration files
- [ ] Using `config.` references instead of duplicating values
- [ ] Proper use of `mkIf`, `mkDefault`, `mkForce`, `mkOverride` where appropriate
- [ ] No large blocks of commented-out code (use git history instead)
- [ ] Modules follow single responsibility principle
- [ ] Configuration is declarative, not imperative

### Module Structure

- [ ] Custom options have proper `types` defined: `grep -r "types\." modules/ | head -20`
- [ ] Options have descriptions where appropriate: `grep -r "description = " modules/ | head -20`
- [ ] Using namespace pattern correctly (no literal imports): `grep -r "imports = \[" modules/`
- [ ] Function wrapping only when `pkgs` is needed
- [ ] Module files start directly with Nix code (no headers)

### State Management

- [ ] Check system.stateVersion consistency: `grep -r "system.stateVersion" modules/`
- [ ] Check home.stateVersion consistency: `grep -r "home.stateVersion" modules/`
- [ ] Verify versions match NixOS release: Both should match your NixOS version
- [ ] No mutable state in `/etc` that should be declarative

### Overlays and Overrides

- [ ] Review all overlays: `grep -r "nixpkgs.overlays" modules/`
- [ ] Check package overrides: `grep -r "override\|overrideAttrs" modules/ | head -20`
- [ ] Verify patches are necessary: `grep -r "patches = " modules/`
- [ ] Check for vendored dependencies: `find modules -name "*.patch" -o -name "vendor"`

### Code Quality

- [ ] No unused variables: Already checked by deadnix in pre-commit
- [ ] No redundant let bindings: `grep -r "let.*in.*let" modules/`
- [ ] Consistent formatting: Already enforced by nixfmt
- [ ] Appropriate use of `lib` functions: `grep -r "lib\." modules/ | head -20`

## Review Summary

### Issues Found

List any issues discovered during review:

1.
2.
3.

### Action Items

Priority tasks to address:

1.
2.
3.

### Risk Assessment

- [ ] **Low Risk**: All checks passed, minor improvements only
- [ ] **Medium Risk**: Some issues found but system functional
- [ ] **High Risk**: Critical issues requiring immediate attention

## Sign-off

- **Review Date**: \_\_\_\_\_\_\_\_\_\_
- **Reviewed By**: \_\_\_\_\_\_\_\_\_\_
- **Current Host**: \_\_\_\_\_\_\_\_\_\_
- **Generation Number**: \_\_\_\_\_\_\_\_\_\_
- **Dendritic Score**: \_\_\_\_\_\_\_\_\_\_
- **Next Review Date**: \_\_\_\_\_\_\_\_\_\_

## Notes

_Additional observations and recommendations:_

---

### Quick Commands Reference

```bash
# Enter dev shell
nix develop

# Run all validations
nix develop -c pre-commit run --all-files

# Check compliance
generation-manager score

# Check store usage
df -h /nix
nix-store --gc --print-dead 2>/dev/null | wc -c | numfmt --to=iec

# Review flake inputs
nix flake metadata

# Find enabled services
grep -r "\.enable = true" modules/ | cut -d: -f1 | sort -u

# Dry build
nixos-rebuild build --flake .#$(hostname)

# View changes
nix-diff $(readlink /run/current-system) result

# Safe cleanup
generation-manager clean 5
```
