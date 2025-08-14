# Dendritic Pattern Migration Plan: Full Functionality Restoration

## Executive Summary

This comprehensive migration plan addresses the integration of ~80+ missing packages and critical configurations from the old NixOS setup into the current Dendritic Pattern configuration. The plan ensures 100% compliance with the golden standard from `mightyiam/infra` while restoring full functionality.

**Key Statistics:**
- **Missing Packages:** 80+ critical packages
- **Missing Services:** 5 major services (VSCode Remote, Enhanced Tailscale, etc.)
- **Missing Features:** Impermanence, Plasma Manager, System76 hardware module
- **Current Compliance:** 95/100 (pending minor fixes)
- **Target:** 100% functionality with 100/100 compliance

---

## Part I: Architecture and Namespace Strategy

### Namespace Organization Principles

Based on the golden standard pattern, configurations must be organized into appropriate namespaces:

1. **`base`** - Core system configuration (all systems)
   - Essential packages (coreutils, git, vim, etc.)
   - Basic networking and SSH
   - System utilities
   - Nix configuration

2. **`pc`** - Desktop/workstation features (extends base)
   - GUI applications
   - Media tools
   - Desktop environment
   - Hardware support

3. **`workstation`** - Development environment (extends pc)
   - Development tools and languages
   - Container/virtualization
   - AI tools
   - Advanced development features

4. **Named Modules** - Optional features (as-needed basis)
   - `nvidia-gpu` - NVIDIA configuration
   - `swap` - Swap configuration
   - `vscode-remote` - VSCode Remote SSH support
   - `impermanence` - Stateless configuration
   - `plasma-manager` - KDE Plasma management

5. **Host-specific** - `configurations.nixos.system76`
   - Hardware-specific configuration
   - Filesystem mounts
   - Host-specific services

### Module Pattern Requirements

All modules must follow these patterns:

```nix
# For modules needing packages:
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = { pkgs, ... }: {
    # Configuration using pkgs
  };
}

# For simple modules:
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = {
    # Direct configuration
  };
}
```

---

## Part II: Phased Migration Plan

## Phase 1: Critical Infrastructure (Week 1)

### 1.1 Fix Current Compliance Issues [IMMEDIATE]

**Actions:**
1. Remove filesystem duplication from `modules/system76/imports.nix`
2. Remove `tests/` directory (migrate to flake checks)
3. Archive and remove `scripts/` directory

```bash
# Quick compliance fix
cp modules/system76/imports.nix modules/system76/imports.nix.backup
# Edit imports.nix to remove lines 25-40 (filesystem config)
rm -rf tests/ scripts/
```

### 1.2 System76 Hardware Module Integration [CRITICAL]

**Create:** `modules/hardware/system76.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.system76-hardware = { pkgs, ... }: {
    imports = [ 
      "${pkgs.nixos-hardware}/nixos/system76"
    ];
    
    hardware.system76.power-daemon.enable = true;
    hardware.system76.kernel-modules.enable = true;
    
    environment.systemPackages = with pkgs; [
      system76-power
      system76-firmware
      system76-keyboard-configurator
    ];
  };
}
```

**Update flake.nix inputs:**
```nix
inputs.nixos-hardware.url = "github:NixOS/nixos-hardware/master";
```

### 1.3 Enhanced NVIDIA Configuration [CRITICAL]

**Update:** `modules/nvidia-gpu.nix`

```nix
{ lib, ... }:
{
  flake.modules.nixos.nvidia-gpu = {
    specialisation.nvidia-gpu.configuration = {
      services.xserver.videoDrivers = [ "nvidia" ];
      
      # Add missing kernel parameters
      boot.kernelParams = [
        "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
        "nvidia.NVreg_EnableGpuFirmware=1"
      ];
      
      boot.blacklistedKernelModules = [ "nouveau" ];
      boot.initrd.kernelModules = [ 
        "nvidia" 
        "nvidia_modeset" 
        "nvidia_uvm" 
        "nvidia_drm" 
      ];
      
      hardware.graphics.extraPackages = with pkgs; [
        nvidia-vaapi-driver
        vaapiVdpau
        libvdpau-va-gl
      ];
    };
  };
  
  nixpkgs.allowedUnfreePackages = [
    "nvidia-x11"
    "nvidia-settings"
  ];
}
```

### 1.4 SSH Configuration Enhancement [SECURITY]

**Update:** `modules/networking/ssh.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.base = {
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;  # Keep secure default
        X11Forwarding = true;  # Add X11 support
        X11DisplayOffset = 10;
        ClientAliveInterval = 60;
        ClientAliveCountMax = 3;
        MaxAuthTries = 3;
      };
      
      # Depend on tailscale when available
      extraConfig = ''
        Protocol 2
      '';
    };
  };
}
```

### 1.5 Boot Configuration Optimization

**Create:** `modules/boot/compression.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.base = {
    boot.initrd.compressor = "zstd";
    boot.loader.systemd-boot.configurationLimit = 3;
    boot.loader.systemd-boot.editor = false;
    boot.loader.systemd-boot.consoleMode = "auto";
  };
}
```

---

## Phase 2: Development Workflow Restoration (Week 1-2)

### 2.1 VSCode Remote SSH Support [HIGH PRIORITY]

**Create:** `modules/development/vscode-remote.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.vscode-remote = { pkgs, ... }: {
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # Core libraries
        curl
        icu
        freetype
        fontconfig
        libxml2
        libxslt
        nspr
        nss
        
        # Graphics
        libGL
        libva
        nvidia-vaapi-driver
        
        # GTK and dependencies
        gtk3
        cairo
        pango
        gdk-pixbuf
        
        # X11
        xorg.libX11
        xorg.libXcomposite
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrandr
        xorg.libXrender
        xorg.libXtst
        xorg.libxcb
        
        # Additional libraries
        alsa-lib
        at-spi2-atk
        at-spi2-core
        atk
        cups
        dbus
        expat
        glib
        libdrm
        libnotify
        libpulseaudio
        libuuid
        libxkbcommon
        mesa
        openssl
        pciutils
        pipewire
        systemd
        vulkan-loader
        wayland
        zlib
      ];
    };
    
    # VSCode Server compatibility
    environment.systemPackages = with pkgs; [
      nodejs_24
      (writeShellScriptBin "fix-vscode-server" ''
        # Helper script for VSCode Server issues
        SERVER_DIR="$HOME/.vscode-server"
        if [ -d "$SERVER_DIR" ]; then
          find "$SERVER_DIR" -name "node" -type f -exec \
            patchelf --set-interpreter ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 {} \;
        fi
      '')
    ];
    
    # SSH environment for VSCode
    programs.ssh.extraConfig = ''
      Host *
        SetEnv PATH=/run/current-system/sw/bin:/usr/bin:/bin
    '';
  };
}
```

### 2.2 Development Languages and Tools

**Create:** `modules/development/languages.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.workstation = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # Languages
      clojure
      clojure-lsp
      temurin-bin-24
      nodejs_24
      yarn
      python312
      rustc
      cargo
      go
      
      # Language servers
      bash-language-server
      yaml-language-server
      json-lsp
      
      # Build tools
      cmake
      gnumake
      gcc
      binutils
    ];
  };
}
```

### 2.3 AI Development Tools

**Create:** `modules/development/ai-tools.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.workstation = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # AI Tools - need to be packaged or use from nixpkgs-unstable
      # claude-code  # Will need custom derivation
      # github-mcp-server  # Will need custom derivation
      
      # Available AI tools
      ollama
      python312Packages.openai
      python312Packages.anthropic
    ];
  };
}
```

### 2.4 Container and Virtualization

**Update:** `modules/virtualization/docker.nix`

```nix
{ config, ... }:
{
  flake.modules.nixos.workstation = {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;  # Change from false
      storageDriver = "overlay2";
      
      # Docker daemon configuration
      daemon.settings = {
        features = {
          buildkit = true;
        };
        log-driver = "json-file";
        log-opts = {
          max-size = "10m";
          max-file = "3";
        };
      };
    };
    
    users.extraGroups.docker.members = [ config.flake.meta.owner.username ];
    
    environment.systemPackages = with pkgs; [
      docker-compose
      docker-buildx
      dive  # Docker image explorer
    ];
  };
}
```

---

## Phase 3: Enhanced System Features (Week 2)

### 3.1 Tailscale Advanced Configuration

**Update:** `modules/networking/vpn.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      openFirewall = true;
      
      # Network optimization
      extraUpFlags = [
        "--advertise-routes=192.168.1.0/24"
        "--advertise-exit-node"
        "--accept-dns=false"
      ];
    };
    
    # Network optimization with ethtool
    systemd.services.tailscale-optimize = {
      after = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${pkgs.ethtool}/bin/ethtool -K tailscale0 rx-udp-gro-forwarding on rx-gro-list off || true
      '';
    };
    
    # Sysctl optimizations
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
    
    environment.systemPackages = with pkgs; [
      ethtool
      ktailctl  # KDE Tailscale GUI
    ];
  };
}
```

### 3.2 Missing Base Packages

**Update:** `modules/base/packages.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.base = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # Core utilities (missing from current)
      aspell
      bat
      dash
      diffutils
      dua
      duf
      eva
      fd
      ffmpeg-full
      fq
      htmlq
      jnv
      jq
      yq
      xq
      imagemagick
      meld
      neovim
      pandoc
      p7zip
      rar
      unrar
      ripgrep
      shfmt
      tealdeer
      uv
      
      # System tools
      dnsutils
      ethtool
      fwupd
      hdparm
      hddtemp
      inotify-tools
      lm_sensors
      lsscsi
      man-pages
      ntpd-rs
      ntpstat
      smartmontools
      
      # File management
      nnn
      ranger
      xdg-utils
    ];
  };
}
```

### 3.3 Media and Desktop Tools

**Create:** `modules/pc/media-tools.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # Media players
      mpv
      vlc
      jellyfin-mpv-shim
      
      # MPV scripts
      (mpv.override {
        scripts = with mpvScripts; [
          thumbfast
          mpris
          quality-menu
        ];
      })
      
      # Audio/Video tools
      audacity
      obs-studio
      kdenlive
      
      # Image tools
      gimp
      inkscape
      krita
      
      # Document tools
      libreoffice
      marktext
      obsidian
      zathura
      mupdf
    ];
    
    # MPV configuration
    environment.etc."mpv/mpv.conf".text = ''
      hwdec=auto
      vo=gpu
      profile=gpu-hq
      scale=ewa_lanczossharp
      cscale=ewa_lanczossharp
    '';
  };
}
```

### 3.4 Communication Applications

**Create:** `modules/pc/communication.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # Email
      thunderbird
      electron-mail
      
      # Chat
      element-desktop
      mattermost-desktop
      discord
      slack
      
      # File sharing
      localsend
      syncthing
      
      # Remote access
      teamviewer
      rustdesk
    ];
    
    # TeamViewer service
    services.teamviewer.enable = true;
  };
}
```

---

## Phase 4: Optional Advanced Features (Week 3)

### 4.1 Impermanence Support

**Create:** `modules/impermanence.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.impermanence = { pkgs, ... }: {
    imports = [ 
      "${inputs.impermanence}/nixos/module.nix"
    ];
    
    environment.persistence."/persist" = {
      hideMounts = true;
      directories = [
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/tailscale"
        "/var/lib/systemd/coredump"
        "/etc/NetworkManager/system-connections"
      ];
      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
      
      users.${config.flake.meta.owner.username} = {
        directories = [
          "Documents"
          "Downloads"
          "Music"
          "Pictures"
          "Videos"
          "Projects"
          ".ssh"
          ".gnupg"
          ".config"
          ".cache"
          ".local/share"
        ];
        files = [
          ".bash_history"
          ".zsh_history"
        ];
      };
    };
  };
}
```

**Update flake.nix:**
```nix
inputs.impermanence.url = "github:nix-community/impermanence";
```

### 4.2 Plasma Manager Integration

**Create:** `modules/plasma-manager.nix`

```nix
{ config, lib, ... }:
{
  flake.modules.nixos.plasma-manager = { pkgs, ... }: {
    imports = [
      "${inputs.plasma-manager}/modules"
    ];
    
    programs.plasma = {
      enable = true;
      
      workspace = {
        lookAndFeel = "org.kde.breezedark.desktop";
        cursor.theme = "breeze_cursors";
        
        windowDecorations = {
          theme = "Breeze";
          library = "org.kde.breeze";
        };
      };
      
      shortcuts = {
        "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" = "Meta+Space";
        "kwin"."Window Maximize" = "Meta+Up";
        "kwin"."Window Minimize" = "Meta+Down";
      };
      
      panels = [
        {
          location = "bottom";
          height = 44;
          widgets = [
            "org.kde.plasma.kickoff"
            "org.kde.plasma.pager"
            "org.kde.plasma.taskmanager"
            "org.kde.plasma.systemtray"
            "org.kde.plasma.digitalclock"
          ];
        }
      ];
    };
  };
}
```

**Update flake.nix:**
```nix
inputs.plasma-manager.url = "github:pjones/plasma-manager";
inputs.plasma-manager.inputs.nixpkgs.follows = "nixpkgs";
inputs.plasma-manager.inputs.home-manager.follows = "home-manager";
```

### 4.3 Custom Package Overlays

**Create:** `modules/meta/custom-packages.nix`

```nix
{ config, lib, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      # BiglyBT custom build
      biglybt-custom = prev.biglybt.overrideAttrs (old: {
        version = "custom";
        src = ./packages/biglybt-custom;
        buildInputs = old.buildInputs ++ [ final.temurin-bin-24 ];
      });
      
      # Other custom packages
      claude-code = final.callPackage ./packages/claude-code { };
      github-mcp-server = final.callPackage ./packages/github-mcp-server { };
    })
  ];
  
  nixpkgs.allowedUnfreePackages = [
    "biglybt"
    "claude-code"
  ];
}
```

---

## Part III: Implementation Guidelines

### File Creation Order

1. **Week 1 - Critical**
   - [ ] Fix compliance issues (imports.nix)
   - [ ] `modules/hardware/system76.nix`
   - [ ] Update `modules/nvidia-gpu.nix`
   - [ ] Update `modules/networking/ssh.nix`
   - [ ] `modules/boot/compression.nix`
   - [ ] `modules/development/vscode-remote.nix`

2. **Week 2 - Development**
   - [ ] `modules/development/languages.nix`
   - [ ] `modules/development/ai-tools.nix`
   - [ ] Update `modules/virtualization/docker.nix`
   - [ ] Update `modules/networking/vpn.nix`
   - [ ] Update `modules/base/packages.nix`

3. **Week 3 - Enhancement**
   - [ ] `modules/pc/media-tools.nix`
   - [ ] `modules/pc/communication.nix`
   - [ ] `modules/impermanence.nix`
   - [ ] `modules/plasma-manager.nix`
   - [ ] `modules/meta/custom-packages.nix`

### Flake Input Updates

Add to `flake.nix`:

```nix
{
  inputs = {
    # Existing inputs...
    
    # New required inputs
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    impermanence.url = "github:nix-community/impermanence";
    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
}
```

### Host Configuration Updates

Update `modules/system76/imports.nix`:

```nix
{ config, ... }:
{
  configurations.nixos.system76.module = {
    imports = with config.flake.modules.nixos; [
      workstation  # Already includes pc → base
      nvidia-gpu   # Optional NVIDIA support
      vscode-remote  # VSCode Remote SSH
      system76-hardware  # Hardware support
      # Optional advanced features
      # impermanence
      # plasma-manager
    ];
    
    # Keep boot configuration here
    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      timeout = 3;
    };
    
    # Remove filesystem configuration (already in filesystem.nix)
  };
}
```

---

## Part IV: Testing and Validation

### Testing Protocol

After each phase:

```bash
# 1. Format check
nix fmt

# 2. Build test
nix build .#nixosConfigurations.system76.config.system.build.toplevel \
  --extra-experimental-features "nix-command flakes pipe-operators"

# 3. Flake check
nix flake check --extra-experimental-features "nix-command flakes pipe-operators"

# 4. Dendritic compliance
grep -r "^#" modules/ | grep -v ".nix:" || echo "✓ No headers found"
grep "abort-on-warn.*true" flake.nix || echo "✗ Missing abort-on-warn"

# 5. Module count (should increase with new modules)
find modules -name "*.nix" | wc -l
```

### Validation Checklist

For each new module:

- [ ] No comment headers (start with Nix code)
- [ ] Correct namespace usage
- [ ] Function wrapper if using `pkgs`
- [ ] No explicit imports (only namespace references)
- [ ] Follows golden standard patterns
- [ ] File in correct directory
- [ ] Builds without warnings

### Integration Testing

```bash
# Test specific features
nix eval .#nixosConfigurations.system76.config.services.tailscale
nix eval .#nixosConfigurations.system76.config.programs.nix-ld
nix eval .#nixosConfigurations.system76.config.virtualisation.docker

# Check package availability
nix eval .#nixosConfigurations.system76.config.environment.systemPackages | grep -c "derivation"
```

---

## Part V: Rollback and Recovery

### Backup Strategy

Before each phase:

```bash
# Full backup
git add -A
git commit -m "backup: before phase X migration"
git tag backup-phase-X

# Configuration backup
sudo cp -r /etc/nixos /etc/nixos.backup.$(date +%Y%m%d)
```

### Rollback Procedures

If issues occur:

```bash
# Git rollback
git reset --hard backup-phase-X

# System rollback
sudo nixos-rebuild switch --rollback

# Emergency boot
# At boot menu, select previous generation
```

### Known Risk Points

1. **NVIDIA Changes** - May affect graphics
   - Test with: `nvidia-smi` after rebuild
   
2. **SSH Changes** - May affect remote access
   - Keep backup session open during changes
   
3. **Boot Parameters** - May affect boot
   - Test with VM first if possible
   
4. **Tailscale Routing** - May affect network
   - Have local access ready

---

## Part VI: Success Metrics

### Functionality Metrics

| Category | Old Config | Current | Target | Status |
|----------|------------|---------|--------|--------|
| Total Packages | 150+ | ~70 | 150+ | 🔄 |
| Development Tools | Full | Partial | Full | 🔄 |
| VSCode Remote | ✅ | ❌ | ✅ | 🔄 |
| Tailscale Features | Advanced | Basic | Advanced | 🔄 |
| Hardware Support | Complete | Partial | Complete | 🔄 |
| Media Tools | Extensive | Basic | Extensive | 🔄 |
| AI Tools | ✅ | ❌ | ✅ | 🔄 |

### Compliance Metrics

| Requirement | Status | Target |
|-------------|--------|--------|
| Dendritic Pattern | 95/100 | 100/100 |
| No Headers | ✅ | ✅ |
| Namespace Usage | ✅ | ✅ |
| No Explicit Imports | ✅ | ✅ |
| Pipe Operators | ✅ | ✅ |
| abort-on-warn | ✅ | ✅ |

### Performance Metrics

- Build time: Should remain under 5 minutes
- Closure size: Monitor with `nix path-info -Sh`
- Boot time: Should not increase significantly

---

## Part VII: Long-term Maintenance

### Documentation Updates

After migration:

1. Update CLAUDE.md with new modules
2. Document custom packages
3. Create MODULE_REFERENCE.md
4. Update build instructions

### Continuous Improvement

1. **Regular Updates**
   ```bash
   nix flake update
   nix build --rebuild
   ```

2. **Package Audits**
   - Review unused packages quarterly
   - Check for security updates
   - Optimize closure size

3. **Pattern Compliance**
   - Regular compliance checks
   - Review against golden standard updates
   - Refactor as patterns evolve

### Future Considerations

1. **Home Manager Integration**
   - Migrate user configs to Home Manager
   - Use home-manager modules for user packages
   
2. **Secret Management**
   - Consider sops-nix or agenix
   - Secure API keys and passwords
   
3. **CI/CD Integration**
   - Automated compliance checks
   - Build testing on commits
   - Deployment automation

---

## Conclusion

This migration plan provides a comprehensive path to restore full functionality while maintaining perfect Dendritic Pattern compliance. The phased approach minimizes risk while ensuring each addition follows the golden standard patterns.

**Key Success Factors:**
1. Maintain namespace discipline
2. Test after each phase
3. Keep compliance at 100/100
4. Document all customizations
5. Follow golden standard patterns exactly

**Timeline:** 2-3 weeks for full implementation
**Risk Level:** Low to Medium (with proper testing)
**Expected Outcome:** Full functionality with improved architecture

---

## Appendix A: Quick Reference

### Namespace Quick Reference

```
base/         → Core system (all systems)
pc/           → Desktop features (extends base)
workstation/  → Development (extends pc)
named/        → Optional features (as-needed)
system76/     → Host-specific
```

### Common Patterns

```nix
# Package module
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ ... ];
  };
}

# Service module
{ config, lib, ... }:
{
  flake.modules.nixos.namespace = {
    services.name = {
      enable = true;
      # config
    };
  };
}

# Named module (optional feature)
{ config, lib, ... }:
{
  flake.modules.nixos.feature-name = {
    # Full configuration
  };
}
```

### Testing Commands

```bash
# Quick build test
nix build .#nixosConfigurations.system76.config.system.build.toplevel

# Apply changes
sudo nixos-rebuild switch --flake .#system76

# Check specific config
nix eval .#nixosConfigurations.system76.config.path.to.option

# List all packages
nix eval .#nixosConfigurations.system76.config.environment.systemPackages --apply 'map (p: p.name)'
```