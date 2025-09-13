# Dendritic Pattern Migration Guide

## Migrating Existing Configurations to the Dendritic Pattern

This guide provides a systematic approach to migrating your existing NixOS configuration to the dendritic pattern. Whether you have a simple single-machine setup or a complex multi-system configuration, this guide will help you transform it into a self-organizing, maintainable system.

## Pre-Migration Assessment

### Analyze Your Current Configuration

Before starting migration, understand what you have:

```bash
# Inventory your current configuration
find /etc/nixos -type f -name "*.nix" | head -20

# Count lines of configuration
find /etc/nixos -type f -name "*.nix" -exec wc -l {} + | sort -n

# Identify import patterns
grep -r "imports = " /etc/nixos

# Find all services you've enabled
grep -r "services\." /etc/nixos | grep "enable = true"

# List custom packages and overlays
grep -r "overlay\|packageOverrides\|mkDerivation" /etc/nixos
```

### Assess Configuration Complexity

Rate your configuration complexity:

**Simple (1-2 files, <200 lines)**

- Single machine
- Basic services
- Few customizations
- Migration time: 1-2 hours

**Moderate (3-10 files, 200-1000 lines)**

- Multiple machines or roles
- Several services
- Some custom packages
- Migration time: 2-4 hours

**Complex (10+ files, 1000+ lines)**

- Many machines with different roles
- Complex service configurations
- Multiple overlays and custom packages
- Migration time: 4-8 hours or more

### Create Migration Checklist

Based on your assessment, create a checklist:

```markdown
## Migration Checklist

- [ ] Backup current configuration
- [ ] List all systems to migrate
- [ ] Identify shared vs system-specific configs
- [ ] Document custom packages/overlays
- [ ] Note hardware-specific settings
- [ ] List all users and their configs
- [ ] Document service configurations
- [ ] Identify secrets management approach
```

## Backing Up Existing Configs

### Step 1: Create Comprehensive Backup

```bash
# Create timestamped backup directory
BACKUP_DIR="$HOME/nixos-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup /etc/nixos
sudo cp -r /etc/nixos "$BACKUP_DIR/"

# Backup current system profile
sudo nix-store --export $(nix-store -qR /run/current-system) > \
  "$BACKUP_DIR/current-system.nar"

# Save current generation info
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system > \
  "$BACKUP_DIR/generations.txt"

# If using home-manager
if [ -d "$HOME/.config/home-manager" ]; then
  cp -r "$HOME/.config/home-manager" "$BACKUP_DIR/"
fi

# Create restore script
cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/usr/bin/env bash
echo "This will restore your NixOS configuration from backup"
echo "Current /etc/nixos will be moved to /etc/nixos.before-restore"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  sudo mv /etc/nixos /etc/nixos.before-restore
  sudo cp -r ./nixos /etc/
  echo "Configuration restored. Run 'sudo nixos-rebuild switch' to apply"
fi
EOF
chmod +x "$BACKUP_DIR/restore.sh"

echo "Backup created at: $BACKUP_DIR"
```

### Step 2: Document Current System State

```bash
# Save system information
cat > "$BACKUP_DIR/system-info.txt" << EOF
Date: $(date)
Hostname: $(hostname)
NixOS Version: $(nixos-version)
Kernel: $(uname -r)
Architecture: $(uname -m)

Active Configuration:
$(readlink /run/current-system)

Hardware Summary:
$(nix-shell -p inxi --run "inxi -F")
EOF
```

## Converting Traditional Imports to Dendritic

### Understanding Import Transformation

**Traditional Pattern:**

```nix
# configuration.nix
{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./users.nix
    ./services/nginx.nix
    ./services/postgresql.nix
    ../shared/base.nix
  ];
}
```

**Dendritic Pattern:**

```nix
# modules/mysystem/imports.nix
{ config, ... }:
{
  configurations.nixos.mysystem.module = {
    imports = with config.flake.nixosModules; [
      base
      networking
      webserver
      database
    ];
  };
}
```

### Step 3: Create Dendritic Structure

```bash
# Initialize new dendritic configuration
mkdir -p ~/nixos-dendritic
cd ~/nixos-dendritic

# Create flake.nix
cat > flake.nix << 'EOF'
{
  nixConfig = {
    abort-on-warn = true;
    extra-experimental-features = [ "pipe-operators" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    home-manager.url = "github:nix-community/home-manager";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ (inputs.import-tree ./modules) ];
      _module.args.rootPath = ./.;
    };
}
EOF

# Create directory structure
mkdir -p modules/{configurations,meta,hardware,services,users}

# Initialize git (required for flakes)
git init
git add flake.nix
```

## Refactoring Modules for Auto-Import

### Step 4: Convert Hardware Configuration

**Traditional hardware-configuration.nix:**

```nix
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };
}
```

**Dendritic modules/mysystem/hardware.nix:**

```nix
{ lib, ... }:
{
  configurations.nixos.mysystem.module = { modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" ];
    boot.kernelModules = [ "kvm-intel" ];

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
    };

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
```

### Step 5: Refactor Service Configurations

**Traditional services/nginx.nix:**

```nix
{ config, pkgs, ... }:
{
  services.nginx = {
    enable = true;
    virtualHosts."example.com" = {
      enableACME = true;
      root = "/var/www/example";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

**Dendritic approach - Split into reusable parts:**

Create `modules/services/nginx.nix`:

```nix
{ ... }:
{
  flake.nixosModules.webserver = {
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
```

Create `modules/sites/example-com.nix`:

```nix
{ ... }:
{
  # Extend the webserver module
  flake.nixosModules.webserver.services.nginx.virtualHosts."example.com" = {
    enableACME = true;
    root = "/var/www/example";
  };
}
```

### Step 6: Migrate User Configurations

**Traditional users.nix:**

```nix
{ config, pkgs, ... }:
{
  users.users.alice = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3..."
    ];
  };

  programs.zsh.enable = true;
}
```

**Dendritic modules/users/alice.nix:**

```nix
{ config, ... }:
{
  flake.nixosModules.base = { pkgs, ... }: {
    users.users.alice = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3..."
      ];
    };
  };

  # Add docker group only on development machines
  flake.nixosModules.development.users.users.alice.extraGroups = [ "docker" ];
}
```

Create `modules/shells/zsh.nix`:

```nix
{
  flake.nixosModules.base.programs.zsh.enable = true;
}
```

## Common Migration Scenarios

### Scenario 1: Single Machine Configuration

**Starting Point:**

```
/etc/nixos/
├── configuration.nix
└── hardware-configuration.nix
```

**Migration Steps:**

1. Create base structure:

```bash
cd ~/nixos-dendritic
mkdir -p modules/{mydesktop,base-config}
```

2. Create configuration framework:

```nix
# modules/configurations/nixos.nix
{ lib, config, ... }:
{
  options.configurations.nixos = lib.mkOption {
    type = lib.types.lazyAttrsOf (
      lib.types.submodule {
        options.module = lib.mkOption {
          type = lib.types.deferredModule;
        };
      }
    );
  };

  config.flake.nixosConfigurations =
    lib.flip lib.mapAttrs config.configurations.nixos (
      name: { module }: lib.nixosSystem { modules = [ module ]; }
    );
}
```

3. Extract base configuration:

```nix
# modules/base.nix
{ ... }:
{
  flake.nixosModules.base = {
    system.stateVersion = "24.11";
    nix.settings.experimental-features = [ "nix-command" "flakes" "pipe-operators" ];

    # Move all common settings here
    time.timeZone = "America/New_York";
    i18n.defaultLocale = "en_US.UTF-8";

    # Common packages
    environment.systemPackages = with pkgs; [
      vim git wget
    ];
  };
}
```

4. Create system-specific module:

```nix
# modules/mydesktop/imports.nix
{ config, ... }:
{
  configurations.nixos.mydesktop.module = {
    imports = [ config.flake.nixosModules.base ];
  };
}

# modules/mydesktop/configuration.nix
{ ... }:
{
  configurations.nixos.mydesktop.module = {
    networking.hostName = "mydesktop";
    # System-specific settings
  };
}

# modules/mydesktop/hardware.nix - Copy from hardware-configuration.nix
```

### Scenario 2: Multiple Machines with Shared Config

**Starting Point:**

```
/etc/nixos/
├── machines/
│   ├── laptop/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   ├── desktop/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   └── server/
│       ├── configuration.nix
│       └── hardware-configuration.nix
└── common/
    ├── base.nix
    ├── users.nix
    └── packages.nix
```

**Migration Strategy:**

1. Identify commonalities:

```bash
# Find duplicate configurations
diff machines/laptop/configuration.nix machines/desktop/configuration.nix

# Identify shared services
grep -h "services\." machines/*/configuration.nix | sort | uniq -c
```

2. Create module hierarchy:

```nix
# modules/pc.nix - Shared by laptop and desktop
{ config, ... }:
{
  flake.nixosModules.pc = {
    imports = [ config.flake.nixosModules.base ];
    services.xserver.enable = true;
    # Other GUI-related config
  };
}

# modules/laptop-hardware.nix
{ config, ... }:
{
  flake.nixosModules.laptop-hardware = {
    imports = [ config.flake.nixosModules.pc ];
    services.tlp.enable = true;
    # Laptop-specific hardware
  };
}

# modules/server.nix
{ config, ... }:
{
  flake.nixosModules.server = {
    imports = [ config.flake.nixosModules.base ];
    services.openssh.enable = true;
    # Server-specific config
  };
}
```

3. Migrate each system:

```nix
# modules/laptop/imports.nix
{ config, ... }:
{
  configurations.nixos.laptop.module = {
    imports = with config.flake.nixosModules; [
      laptop-hardware
      development  # If it's a dev machine
    ];
  };
}
```

### Scenario 3: Complex Multi-Role Systems

**Starting Point:**

```
/etc/nixos/
├── hosts/
│   ├── prod-web-1/
│   ├── prod-web-2/
│   ├── prod-db-1/
│   ├── staging-web/
│   └── dev-workstation/
├── roles/
│   ├── webserver.nix
│   ├── database.nix
│   ├── monitoring.nix
│   └── development.nix
├── environments/
│   ├── production.nix
│   ├── staging.nix
│   └── development.nix
└── lib/
    └── helpers.nix
```

**Migration Approach:**

1. Convert roles to named modules:

```nix
# modules/roles/webserver.nix
{ config, ... }:
{
  flake.nixosModules.webserver-role = {
    services.nginx.enable = true;
    # Webserver configuration
  };
}

# modules/roles/database.nix
{ config, ... }:
{
  flake.nixosModules.database-role = {
    services.postgresql.enable = true;
    # Database configuration
  };
}
```

2. Convert environments to modules:

```nix
# modules/environments/production.nix
{ config, ... }:
{
  flake.nixosModules.production-env = {
    security.sudo.wheelNeedsPassword = true;
    services.fail2ban.enable = true;
    # Production hardening
  };
}
```

3. Compose systems from roles and environments:

```nix
# modules/prod-web-1/imports.nix
{ config, ... }:
{
  configurations.nixos.prod-web-1.module = {
    imports = with config.flake.nixosModules; [
      base
      server
      webserver-role
      production-env
      monitoring
    ];
  };
}
```

## Troubleshooting Migration Issues

### Issue: Infinite Recursion

**Symptom:**

```
error: infinite recursion encountered
```

**Common Causes and Solutions:**

1. **Circular module dependencies:**

```nix
# BAD: moduleA imports moduleB, moduleB imports moduleA
# GOOD: Extract common parts to a third module
```

2. **Self-referential configuration:**

```nix
# BAD
flake.nixosModules.base = {
  networking.hostName = config.networking.hostName;
};

# GOOD
flake.nixosModules.base = {
  networking.hostName = lib.mkDefault "defaultname";
};
```

### Issue: Attribute Missing

**Symptom:**

```
error: attribute 'something' missing
```

**Solutions:**

1. Check module is being imported:

```nix
# Verify file exists in modules/
ls modules/

# Check for underscore prefix (ignored files)
# _module.nix won't be imported
```

2. Verify attribute path:

```nix
# Use nix repl to explore
nix repl --extra-experimental-features pipe-operators
> :lf .
> config.flake.nixosModules.<tab>
```

### Issue: Option Already Defined

**Symptom:**

```
error: The option `something' is defined multiple times
```

**Solutions:**

1. Use `mkDefault` for overridable values:

```nix
# In base module
networking.hostName = lib.mkDefault "default";

# In specific system
networking.hostName = "specific";  # Overrides default
```

2. Use `mkMerge` for lists:

```nix
environment.systemPackages = lib.mkMerge [
  (with pkgs; [ vim git ])
  (with pkgs; [ firefox ])
];
```

### Issue: Hardware Configuration Not Applied

**Symptom:**
System boots but hardware features missing

**Solution:**
Ensure hardware module is properly scoped:

```nix
# modules/mysystem/hardware.nix
{ ... }:
{
  configurations.nixos.mysystem.module = {  # Correct scope
    boot.initrd.availableKernelModules = [ ... ];
    # Hardware config
  };
}
```

## Migration Verification Checklist

### Pre-Deployment Verification

```bash
# 1. Check flake structure
nix flake show --extra-experimental-features pipe-operators

# 2. Verify no evaluation errors
nix flake check --extra-experimental-features pipe-operators

# 3. Build configuration
nix build .#nixosConfigurations.mysystem.config.system.build.toplevel \
  --extra-experimental-features pipe-operators

# 4. Compare with old configuration
nix-diff $(readlink /run/current-system) ./result

# 5. Test in VM first
nix build .#nixosConfigurations.mysystem.config.system.build.vm \
  --extra-experimental-features pipe-operators
./result/bin/run-*-vm
```

### Post-Migration Verification

```bash
# 1. Check system boots correctly
sudo journalctl -b

# 2. Verify services are running
systemctl status

# 3. Check hardware detection
nix-shell -p inxi --run "inxi -F"

# 4. Verify user sessions
loginctl list-sessions

# 5. Test critical services
curl localhost  # If running web server
```

### Rollback Plan

If issues occur after migration:

```bash
# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo nixos-rebuild --rollback switch

# Or boot into previous generation from bootloader
# Select previous generation in boot menu
```

## Progressive Migration Strategy

### Phase 1: Minimal Migration (Day 1)

Goal: Get system booting with dendritic pattern

1. Migrate only essential configuration
2. Keep complex services in single file initially
3. Focus on getting system operational

```nix
# Start simple
modules/
├── configurations/nixos.nix
├── base.nix
└── mysystem/
    ├── imports.nix
    ├── hardware.nix
    └── configuration.nix  # Everything else temporarily
```

### Phase 2: Service Extraction (Week 1)

Goal: Extract services into modules

1. Move each service to its own module
2. Create named modules for service groups
3. Test each extraction

```nix
# Extract services
modules/
├── services/
│   ├── nginx.nix
│   ├── postgresql.nix
│   └── docker.nix
```

### Phase 3: User Migration (Week 2)

Goal: Migrate user configurations

1. Setup Home Manager integration
2. Move user configs to modules
3. Extract dotfiles

### Phase 4: Optimization (Month 1)

Goal: Refine and optimize

1. Identify patterns and create abstractions
2. Reduce duplication
3. Improve organization

## Best Practices for Migration

### 1. Start with Working Configuration

Never migrate a broken configuration. Fix issues first.

### 2. Migrate Incrementally

Don't try to migrate everything at once. Start with core functionality.

### 3. Test Continuously

After each change:

```bash
nix flake check --extra-experimental-features pipe-operators
```

### 4. Keep Backup Accessible

```bash
# Keep backup configuration ready
sudo ln -s ~/nixos-backup/nixos /etc/nixos-backup
```

### 5. Document Changes

Create a migration log:

```markdown
# Migration Log

## 2024-01-15

- Migrated base configuration
- Extracted hardware settings
- Issue: Network manager not starting
- Fixed: Added to base module

## 2024-01-16

- Migrated user configurations
- Setup Home Manager
```

### 6. Use Version Control

```bash
git init
git add .
git commit -m "Initial dendritic migration"

# Create checkpoint commits
git commit -m "Phase 1: Base system working"
git commit -m "Phase 2: Services extracted"
```

## Common Patterns to Recognize

### Package Sets

**Before:**

```nix
environment.systemPackages = with pkgs; [
  # Development
  git vim vscode
  # System
  htop tree
  # Network
  wget curl
];
```

**After (separate modules):**

```nix
# modules/packages/development.nix
flake.nixosModules.development.environment.systemPackages =
  with pkgs; [ git vim vscode ];

# modules/packages/system-tools.nix
flake.nixosModules.base.environment.systemPackages =
  with pkgs; [ htop tree ];
```

### Service Groups

Recognize related services:

- Web stack: nginx + certbot + firewall rules
- Database: postgresql + backup + monitoring
- Development: docker + podman + virtualbox

### Hardware Patterns

Common hardware groupings:

- Laptop: battery + wifi + touchpad + brightness
- Desktop: multiple monitors + audio + gaming
- Server: RAID + IPMI + redundant networking

## Success Indicators

Your migration is successful when:

- [ ] System boots without errors
- [ ] All services start correctly
- [ ] Users can log in
- [ ] No evaluation warnings
- [ ] Can rebuild without network (pure evaluation)
- [ ] Configuration is more maintainable
- [ ] Easy to add new systems
- [ ] Clear separation of concerns
- [ ] No literal path imports remain

## Post-Migration Benefits

After successful migration:

1. **Refactoring becomes trivial** - Move files without updating imports
2. **Adding systems is easy** - Compose from existing modules
3. **Testing improves** - Each configuration is automatically tested
4. **Collaboration enhances** - Clear structure helps others contribute
5. **Maintenance reduces** - No import management overhead

Remember: The dendritic pattern is about gradual improvement. Your configuration will continue to evolve and improve over time as you discover better organizations and patterns.
