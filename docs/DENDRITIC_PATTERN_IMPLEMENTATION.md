# Dendritic Pattern Implementation Guide

## Step-by-Step Implementation of the Dendritic Pattern

This guide provides a complete, actionable implementation path for adopting the dendritic pattern in your Nix configuration. Follow these steps to transform your traditional setup into a self-organizing, maintainable system.

## Prerequisites and Requirements

### System Requirements

```bash
# Check Nix version (must be 2.13 or higher)
nix --version

# Enable required experimental features globally
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes pipe-operators" >> ~/.config/nix/nix.conf
```

### Critical: Pipe Operators

**The dendritic pattern REQUIRES pipe operators.** Every Nix command must include:

```bash
--extra-experimental-features pipe-operators
```

Example:

```bash
nix flake check --extra-experimental-features pipe-operators
nix build .#nixosConfigurations.mysystem.config.system.build.toplevel --extra-experimental-features pipe-operators
```

### Knowledge Prerequisites

- Basic understanding of Nix flakes
- Familiarity with NixOS module system
- Understanding of attribute sets and functions
- Comfort with command-line operations

## Initial Flake.nix Setup with Import-Tree

### Step 1: Create the Foundation Flake

Create `flake.nix` in your configuration root:

```nix
{
  # CRITICAL: Enable pipe operators
  nixConfig = {
    abort-on-warn = true;
    extra-experimental-features = [ "pipe-operators" ];
    allow-import-from-derivation = false;
  };

  inputs = {
    # Core dependencies
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # The magic: automatic module import
    import-tree.url = "github:vic/import-tree";

    # Optional but recommended
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # THE CORE MAGIC: All modules automatically imported
      imports = [ (inputs.import-tree ./modules) ];

      # Provide root path for modules to reference
      _module.args.rootPath = ./.;
    };
}
```

### Step 2: Initialize the Flake

```bash
# Initialize git repository (required for flakes)
git init

# Add flake.nix
git add flake.nix

# Generate lock file
nix flake lock --extra-experimental-features pipe-operators

# Verify it works
nix flake show --extra-experimental-features pipe-operators
```

## Creating the modules/ Directory Structure

### Step 3: Create Directory Hierarchy

```bash
# Create the essential directories
mkdir -p modules/{configurations,meta,hardware,systems}

# Create system-specific directories (example)
mkdir -p modules/mysystem

# Optional organizational directories
mkdir -p modules/{shells,networking,audio,security}
```

### Directory Structure Explanation

```
modules/
├── configurations/     # Framework for NixOS/Home-Manager configs
├── meta/              # Repository tooling (CI, formatting, etc.)
├── hardware/          # Hardware-specific modules
├── systems/           # Alternative to per-system directories
├── shells/            # Shell configurations
├── networking/        # Network-related modules
└── [system-name]/     # System-specific configurations
```

## Setting Up Configurations Framework

### Step 4: Create NixOS Configuration Framework

Create `modules/configurations/nixos.nix`:

```nix
{ lib, config, ... }:
{
  options.configurations.nixos = lib.mkOption {
    type = lib.types.lazyAttrsOf (
      lib.types.submodule {
        options.module = lib.mkOption {
          type = lib.types.deferredModule;
          description = "NixOS module for this configuration";
        };
      }
    );
    default = {};
    description = "NixOS system configurations";
  };

  config.flake = {
    # Transform configurations into NixOS systems
    nixosConfigurations = lib.flip lib.mapAttrs config.configurations.nixos (
      name: { module }:
        lib.nixosSystem {
          modules = [ module ];
        }
    );

    # Automatically create checks for each configuration
    checks =
      config.flake.nixosConfigurations
      |> lib.mapAttrsToList (
        name: nixos: {
          ${nixos.config.nixpkgs.hostPlatform.system} = {
            "configurations/nixos/${name}" = nixos.config.system.build.toplevel;
          };
        }
      )
      |> lib.mkMerge;
  };
}
```

### Step 5: Create Base Module

Create `modules/base.nix`:

```nix
{ lib, config, inputs, ... }:
{
  flake.modules.nixos.base = { pkgs, ... }: {
    # Essential for all systems
    system.stateVersion = "24.11";  # Set to your NixOS version

    # Critical: Enable experimental features
    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
        trusted-users = [ "root" "@wheel" ];
        auto-optimise-store = true;
      };

      # Use latest stable Nix
      package = pkgs.nixVersions.stable;
    };

    # Basic system configuration
    time.timeZone = "UTC";  # Override in specific systems
    i18n.defaultLocale = "en_US.UTF-8";

    # Essential packages for all systems
    environment.systemPackages = with pkgs; [
      vim
      git
      wget
      curl
    ];

    # Enable basic services
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };
}
```

## Implementing Named Modules Correctly

### Step 6: Create Hierarchical Named Modules

Create `modules/pc.nix` for desktop/laptop systems:

```nix
{ config, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    imports = [ config.flake.modules.nixos.base ];

    # GUI-related configuration
    services.xserver = {
      enable = true;
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
    };

    # Audio
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Networking for desktop/laptop
    networking.networkmanager.enable = true;

    # Common desktop packages
    environment.systemPackages = with pkgs; [
      firefox
      thunderbird
    ];
  };
}
```

Create `modules/laptop.nix` for laptop-specific features:

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.laptop = { ... }: {
    imports = [ config.flake.modules.nixos.pc ];

    # Power management
    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        START_CHARGE_THRESH_BAT0 = 75;
        STOP_CHARGE_THRESH_BAT0 = 80;
      };
    };

    # Laptop-specific services
    services.thermald.enable = true;
    services.auto-cpufreq.enable = true;

    # Touchpad support
    services.xserver.libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        tapping = true;
      };
    };

    # Brightness control
    programs.light.enable = true;
  };
}
```

Create `modules/server.nix` for server systems:

```nix
{ config, ... }:
{
  flake.modules.nixos.server = { ... }: {
    imports = [ config.flake.modules.nixos.base ];

    # Server-specific settings
    services.openssh.settings.PermitRootLogin = "prohibit-password";

    # Disable GUI
    services.xserver.enable = false;

    # Enable monitoring
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    # Automatic updates
    system.autoUpgrade = {
      enable = true;
      allowReboot = true;
      dates = "02:00";
    };

    # Firewall
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ];
    };
  };
}
```

## System Configuration Composition

### Step 7: Create Your First System

Create `modules/mysystem/imports.nix`:

```nix
{ config, ... }:
{
  configurations.nixos.mysystem.module = {
    imports = with config.flake.modules.nixos; [
      base
      pc
      # Add other modules as needed
    ];
  };
}
```

Create `modules/mysystem/hardware.nix`:

```nix
{ lib, ... }:
{
  configurations.nixos.mysystem.module = { config, pkgs, modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-intel" ];
    boot.extraModulePackages = [ ];

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
    };

    swapDevices = [ ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
```

Create `modules/mysystem/configuration.nix`:

```nix
{ config, ... }:
{
  configurations.nixos.mysystem.module = { pkgs, ... }: {
    networking.hostName = "mysystem";

    # Bootloader
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Users
    users.users.myuser = {
      isNormalUser = true;
      description = "My User";
      extraGroups = [ "wheel" "networkmanager" ];
      shell = pkgs.bash;
    };

    # System-specific packages
    environment.systemPackages = with pkgs; [
      htop
      neovim
    ];
  };
}
```

## Integration with Home Manager

### Step 8: Setup Home Manager Integration

Create `modules/home-manager/nixos.nix`:

```nix
{ config, inputs, lib, ... }:
{
  flake.modules.nixos.base = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    home-manager = {
      # Use system packages
      useGlobalPkgs = true;

      # Pass through inputs
      extraSpecialArgs = {
        inherit inputs;
      };

      # User configurations will be added by other modules
      users = {};
    };
  };
}
```

Create `modules/home-manager/base.nix`:

```nix
{ config, ... }:
{
  flake.modules.homeManager.base = { ... }: {
    # Essential for all users
    home.stateVersion = "24.11";
    programs.home-manager.enable = true;

    # Basic programs
    programs.bash.enable = true;
    programs.git.enable = true;

    # XDG configuration
    xdg.enable = true;
    xdg.configFile."nix/nix.conf".text = ''
      experimental-features = nix-command flakes pipe-operators
    '';
  };
}
```

### Step 9: Configure User with Home Manager

Create `modules/users/myuser.nix`:

```nix
{ config, ... }:
{
  # System-level user configuration
  flake.modules.nixos.base = { pkgs, ... }: {
    users.users.myuser = {
      isNormalUser = true;
      description = "My User";
      extraGroups = [ "wheel" "networkmanager" ];
      shell = pkgs.bash;
    };

    # Link to Home Manager
    home-manager.users.myuser = {
      imports = [ config.flake.modules.homeManager.base ];
    };
  };

  # Home Manager configuration
  flake.modules.homeManager.base = { pkgs, ... }: {
    home.username = "myuser";
    home.homeDirectory = "/home/myuser";

    programs.git = {
      userName = "My Name";
      userEmail = "my.email@example.com";
    };

    home.packages = with pkgs; [
      tree
      ripgrep
      fd
    ];
  };
}
```

## Testing and Verification

### Step 10: Verify Your Configuration

```bash
# Check flake outputs
nix flake show --extra-experimental-features pipe-operators

# Check for evaluation errors
nix flake check --extra-experimental-features pipe-operators

# Build the system configuration (without switching)
nix build .#nixosConfigurations.mysystem.config.system.build.toplevel \
  --extra-experimental-features pipe-operators

# Build a specific check
nix build .#checks.x86_64-linux."configurations/nixos/mysystem" \
  --extra-experimental-features pipe-operators
```

### Step 11: Test in a VM (Optional but Recommended)

```bash
# Build a VM
nix build .#nixosConfigurations.mysystem.config.system.build.vm \
  --extra-experimental-features pipe-operators

# Run the VM
./result/bin/run-mysystem-vm
```

### Step 12: Deploy to Your System

```bash
# Build and switch to new configuration
sudo nixos-rebuild switch --flake .#mysystem \
  --extra-experimental-features pipe-operators

# Or just build without switching
sudo nixos-rebuild build --flake .#mysystem \
  --extra-experimental-features pipe-operators
```

## Advanced Module Patterns

### Conditional Module Extension

Create `modules/nvidia-gpu.nix`:

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.nvidia-gpu = { config, ... }: {
    # Only for systems that import this module
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # CUDA support
    hardware.opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
    };
  };
}
```

### Polyglot Modules (NixOS + Home Manager)

Create `modules/development.nix`:

```nix
{ config, ... }:
{
  # NixOS-level development tools
  flake.modules.nixos.development = { pkgs, ... }: {
    virtualisation.docker.enable = true;
    programs.direnv.enable = true;

    environment.systemPackages = with pkgs; [
      gcc
      gnumake
      nodejs
      python3
    ];
  };

  # Home Manager development setup
  flake.modules.homeManager.development = { pkgs, ... }: {
    programs.vscode = {
      enable = true;
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        rust-lang.rust-analyzer
      ];
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
```

### Module with Options

Create `modules/backup.nix`:

```nix
{ config, lib, ... }:
{
  options.flake.backup = {
    enable = lib.mkEnableOption "backup system";

    repository = lib.mkOption {
      type = lib.types.str;
      description = "Backup repository path";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ "/home" ];
      description = "Paths to backup";
    };
  };

  config = lib.mkIf config.flake.backup.enable {
    flake.modules.nixos.base = { pkgs, ... }: {
      services.restic.backups.main = {
        repository = config.flake.backup.repository;
        paths = config.flake.backup.paths;
        timerConfig = {
          OnCalendar = "daily";
        };
      };
    };
  };
}
```

## Formatting and Development Tools

### Step 13: Setup Code Formatting

Create `modules/meta/fmt.nix`:

```nix
{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = { pkgs, ... }: {
    treefmt = {
      projectRootFile = "flake.nix";

      programs = {
        # Nix formatting
        nixfmt.enable = true;

        # Other formatters
        prettier = {
          enable = true;
          includes = [ "*.md" "*.yaml" "*.yml" "*.json" ];
        };

        shfmt.enable = true;
        rustfmt.enable = true;
      };

      settings.formatter.nixfmt = {
        includes = [ "*.nix" ];
      };
    };
  };
}
```

### Step 14: Create Development Shell

Create `modules/meta/devshell.nix`:

```nix
{ config, lib, ... }:
{
  perSystem = { pkgs, config, ... }: {
    devShells.default = pkgs.mkShell {
      name = "dendritic-dev";

      packages = with pkgs; [
        # Nix tools
        nixpkgs-fmt
        nil  # Nix LSP
        nix-tree
        nix-diff

        # Utilities
        git
        just
        fd
        ripgrep

        # From treefmt
        config.treefmt.build.wrapper
      ];

      shellHook = ''
        echo "Dendritic Pattern Development Shell"
        echo "Remember: Always use --extra-experimental-features pipe-operators"
        echo ""
        echo "Commands:"
        echo "  nix fmt                - Format all code"
        echo "  nix flake check        - Run all checks"
        echo "  nix build .#<system>   - Build a system"
        echo ""
        alias nix='nix --extra-experimental-features pipe-operators'
      '';
    };
  };
}
```

## Common Module Patterns

### Package Management

Create `modules/packages/cli-tools.nix`:

```nix
{ ... }:
{
  flake.modules.nixos.base = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # File management
      tree
      fd
      ripgrep
      eza

      # System monitoring
      htop
      btop
      iotop

      # Network tools
      wget
      curl
      dig
      nmap
    ];
  };
}
```

### Service Configuration

Create `modules/services/nginx.nix`:

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.webserver = { ... }: {
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
```

### Hardware Detection

Create `modules/hardware/auto-detect.nix`:

```nix
{ lib, ... }:
{
  flake.modules.nixos.base = { config, ... }: {
    # Auto-detect video drivers
    services.xserver.videoDrivers = lib.mkDefault (
      if config.hardware.nvidia.modesetting.enable then [ "nvidia" ]
      else if config.hardware.amdgpu.enable then [ "amdgpu" ]
      else [ "modesetting" ]
    );
  };
}
```

## Verification Checklist

Before deploying, ensure:

- [ ] `flake.nix` has `pipe-operators` in `nixConfig.extra-experimental-features`
- [ ] All modules are in `modules/` directory
- [ ] No literal path imports (no `./something.nix`)
- [ ] Base module exists and is imported by other modules
- [ ] System configuration has `imports`, `hardware`, and basic settings
- [ ] `nix flake check --extra-experimental-features pipe-operators` passes
- [ ] Can build system configuration without errors
- [ ] Home Manager integration works (if used)
- [ ] Development shell loads correctly
- [ ] Formatting works with `nix fmt`

## Next Steps

1. **Add More Modules:** Gradually add functionality through new modules
2. **Refine Organization:** Reorganize modules as patterns emerge
3. **Setup CI/CD:** Add GitHub Actions for automatic testing
4. **Document Specifics:** Add README for your specific setup
5. **Share Modules:** Consider publishing reusable modules

## Getting Help

- Check error messages carefully - Nix provides detailed error information
- Use `nix repl` to explore your configuration interactively
- Run `nix flake show` to see all outputs
- Enable `--show-trace` for detailed error traces
- Remember: **Always use `--extra-experimental-features pipe-operators`**

The dendritic pattern will transform how you manage Nix configurations. Start simple, grow organically, and enjoy the freedom of automatic module discovery!
