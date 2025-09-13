# Dendritic Pattern Best Practices

## Advanced Patterns and Practices for the Dendritic Pattern

This guide covers advanced techniques, optimizations, and best practices for sophisticated dendritic pattern implementations. These patterns emerge from real-world usage and represent the evolution of dendritic configurations.

## Polyglot Modules (NixOS/Home-Manager/Nix-on-Droid)

### Unified Module Design

The dendritic pattern excels at managing multiple configuration types from a single module:

```nix
# modules/git-everywhere.nix
{ config, ... }:
{
  # NixOS system configuration
  flake.nixosModules.base = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.git ];
    programs.git = {
      enable = true;
      lfs.enable = true;
    };
  };

  # Home Manager configuration
  flake.homeManagerModules.base = {
    programs.git = {
      enable = true;
      delta.enable = true;
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };
  };

  # Nix-on-Droid configuration
  flake.nixOnDroidModules.base = {
    environment.packages = [ pkgs.git ];
    user.shell = "${pkgs.git}/bin/git";
  };

  # Darwin (macOS) configuration
  flake.darwinModules.base = {
    environment.systemPackages = [ pkgs.git ];
    programs.git.enable = true;
  };
}
```

### Cross-Platform Abstractions

Create abstractions that work across platforms:

```nix
# modules/shell-environment.nix
{ config, lib, ... }:
let
  shellAliases = {
    ll = "ls -la";
    ".." = "cd ..";
    "..." = "cd ../..";
    gs = "git status";
    gc = "git commit";
  };

  shellVariables = {
    EDITOR = "nvim";
    PAGER = "less";
  };
in
{
  # Apply to all platforms
  flake.nixosModules.base.environment = {
    shellAliases = shellAliases;
    variables = shellVariables;
  };

  flake.homeManagerModules.base.home = {
    shellAliases = shellAliases;
    sessionVariables = shellVariables;
  };

  flake.darwinModules.base.environment = {
    shellAliases = shellAliases;
    variables = shellVariables;
  };
}
```

### Platform-Specific Extensions

Handle platform differences elegantly:

```nix
# modules/development-environment.nix
{ config, lib, inputs, ... }:
{
  # Shared development tools
  flake.nixosModules.allPlatforms = {
    development = { pkgs, ... }: {
      packages = with pkgs; [
        rustc
        cargo
        nodejs
        python3
      ];
    };
  };

  # Linux-specific (NixOS)
  flake.nixosModules.development = { pkgs, ... }: {
    imports = [ config.flake.nixosModules.allPlatforms.development ];

    # Linux-only tools
    virtualisation.docker.enable = true;
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  };

  # macOS-specific (Darwin)
  flake.darwinModules.development = { pkgs, ... }: {
    imports = [ config.flake.nixosModules.allPlatforms.development ];

    # macOS-only configuration
    homebrew.casks = [ "docker" ];
  };

  # Mobile-specific (Nix-on-Droid)
  flake.nixOnDroidModules.development = { pkgs, ... }: {
    # Subset for mobile
    environment.packages = with pkgs; [
      git
      vim
      openssh
    ];
  };
}
```

## Conditional Module Extension

### Smart Module Loading

Load modules based on system capabilities:

```nix
# modules/smart-gpu.nix
{ config, lib, ... }:
{
  flake.nixosModules.base = { config, lib, ... }:
  let
    hasNvidia = builtins.elem "nvidia" (config.services.xserver.videoDrivers or []);
    hasAmd = builtins.elem "amdgpu" (config.services.xserver.videoDrivers or []);
  in {
    # Conditional GPU configuration
    hardware.opengl = {
      enable = lib.mkDefault (hasNvidia || hasAmd);
      driSupport = true;
      driSupport32Bit = lib.mkDefault (hasNvidia || hasAmd);

      extraPackages = with pkgs;
        lib.optionals hasAmd [ amdvlk rocm-opencl-icd ]
        ++ lib.optionals hasNvidia [ nvidia-vaapi-driver ];
    };

    # Conditional kernel modules
    boot.initrd.kernelModules =
      lib.optionals hasNvidia [ "nvidia" "nvidia_modeset" "nvidia_uvm" ]
      ++ lib.optionals hasAmd [ "amdgpu" ];
  };
}
```

### Feature Detection

Automatically enable features based on hardware:

```nix
# modules/hardware/auto-features.nix
{ config, lib, ... }:
{
  flake.nixosModules.base = { config, lib, pkgs, ... }:
  let
    # Detect hardware capabilities
    hasBluetooth = config.hardware.bluetooth.enable or
      (builtins.elem "bluetooth" (config.boot.kernelModules or []));

    hasWifi = builtins.any (iface: iface.type == "wlan")
      (lib.attrValues (config.networking.interfaces or {}));

    isSSD = config.fileSystems."/".device.type or "hdd" == "ssd";
  in {
    # Auto-enable based on detection
    services.blueman.enable = lib.mkDefault hasBluetooth;

    networking.networkmanager.wifi.backend =
      lib.mkDefault (if hasWifi then "iwd" else "wpa_supplicant");

    services.fstrim.enable = lib.mkDefault isSSD;

    # Optimize for detected hardware
    boot.kernel.sysctl = lib.mkIf isSSD {
      "vm.swappiness" = 1;
      "vm.vfs_cache_pressure" = 50;
    };
  };
}
```

### Dynamic Module Generation

Generate modules based on data:

```nix
# modules/dynamic/containers.nix
{ config, lib, ... }:
let
  containerSpecs = {
    postgres = {
      image = "postgres:15";
      ports = [ "5432:5432" ];
      environment = {
        POSTGRES_PASSWORD = "secret";
      };
    };
    redis = {
      image = "redis:7";
      ports = [ "6379:6379" ];
    };
    nginx = {
      image = "nginx:latest";
      ports = [ "80:80" "443:443" ];
      volumes = [ "/srv/www:/usr/share/nginx/html:ro" ];
    };
  };
in
{
  # Generate container modules dynamically
  flake.nixosModules = lib.mapAttrs (name: spec: {
    virtualisation.oci-containers.containers.${name} = {
      inherit (spec) image;
      ports = spec.ports or [];
      environment = spec.environment or {};
      volumes = spec.volumes or [];
      autoStart = true;
    };
  }) containerSpecs;
}
```

## Managing Multiple Systems

### System Registry Pattern

Centralize system definitions:

```nix
# modules/systems/registry.nix
{ config, lib, ... }:
let
  systems = {
    # Production servers
    prod-web-1 = {
      type = "server";
      roles = [ "webserver" "monitoring" ];
      location = "us-east-1";
      ip = "10.0.1.10";
    };
    prod-web-2 = {
      type = "server";
      roles = [ "webserver" "monitoring" ];
      location = "us-west-2";
      ip = "10.0.2.10";
    };
    prod-db-1 = {
      type = "server";
      roles = [ "database" "backup" ];
      location = "us-east-1";
      ip = "10.0.1.20";
    };

    # Workstations
    dev-laptop = {
      type = "laptop";
      roles = [ "development" "vpn-client" ];
      user = "alice";
    };
    office-desktop = {
      type = "desktop";
      roles = [ "development" "build-agent" ];
      user = "bob";
    };
  };
in
{
  # Generate configurations from registry
  configurations.nixos = lib.mapAttrs (hostname: spec: {
    module = { config, ... }: {
      imports = with config.flake.nixosModules; [
        base
        spec.type
      ] ++ map (role: config.flake.nixosModules.${role}) spec.roles;

      networking.hostName = hostname;
      networking.interfaces.eth0.ipv4.addresses = lib.optional (spec ? ip) {
        address = spec.ip;
        prefixLength = 24;
      };

      # Location-specific settings
      time.timeZone =
        if lib.hasPrefix "us-east" (spec.location or "")
        then "America/New_York"
        else if lib.hasPrefix "us-west" (spec.location or "")
        then "America/Los_Angeles"
        else "UTC";
    };
  }) systems;

  # Export system metadata for other uses
  flake.systems = systems;
}
```

### Multi-System Deployment

Coordinate deployments across systems:

```nix
# modules/deployment/orchestration.nix
{ config, lib, ... }:
{
  # Define deployment groups
  flake.deploymentGroups = {
    webservers = [ "prod-web-1" "prod-web-2" ];
    databases = [ "prod-db-1" "prod-db-2" ];
    all-prod = config.flake.deploymentGroups.webservers
      ++ config.flake.deploymentGroups.databases;
  };

  # Generate deployment scripts
  perSystem = { pkgs, ... }: {
    packages = lib.mapAttrs (group: systems:
      pkgs.writeShellScriptBin "deploy-${group}" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "Deploying to ${group}: ${lib.concatStringsSep ", " systems}"

        ${lib.concatMapStringsSep "\n" (system: ''
          echo "Deploying ${system}..."
          nixos-rebuild switch \
            --flake .#${system} \
            --target-host ${system} \
            --extra-experimental-features pipe-operators \
            --use-remote-sudo
        '') systems}

        echo "Deployment complete!"
      ''
    ) config.flake.deploymentGroups;
  };
}
```

### Shared State Management

Manage shared state across systems:

```nix
# modules/state/shared.nix
{ config, lib, ... }:
{
  options.flake.sharedState = {
    sshKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "SSH public keys for users";
    };

    certificates = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "TLS certificates";
    };

    wireguardPeers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          publicKey = lib.mkOption { type = lib.types.str; };
          endpoint = lib.mkOption { type = lib.types.str; };
          allowedIPs = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };
      });
      default = [];
    };
  };

  config = {
    # Populate shared state
    flake.sharedState.sshKeys = {
      alice = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...";
      bob = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...";
    };

    # Use shared state in modules
    flake.nixosModules.base = {
      users.users = lib.mapAttrs (name: key: {
        openssh.authorizedKeys.keys = [ key ];
      }) config.flake.sharedState.sshKeys;
    };
  };
}
```

## Handling Hardware Variations

### Hardware Profiles

Create reusable hardware profiles:

```nix
# modules/hardware/profiles/dell-xps-13.nix
{ config, lib, ... }:
{
  flake.nixosModules.dell-xps-13 = { pkgs, ... }: {
    # Specific kernel modules
    boot.initrd.kernelModules = [ "i915" ];
    boot.kernelParams = [
      "mem_sleep_default=deep"
      "nvme.noacpi=1"
    ];

    # Hardware-specific packages
    environment.systemPackages = with pkgs; [
      dell-command-configure
      thermald
    ];

    # Power management
    services.thermald.enable = true;
    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        STOP_CHARGE_THRESH_BAT0 = 90;
      };
    };

    # Touchpad configuration
    services.xserver.libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        middleEmulation = false;
        tapping = true;
      };
    };
  };
}
```

### Automatic Hardware Detection

Use nixos-facter for hardware detection:

```nix
# modules/hardware/auto-detect.nix
{ config, lib, ... }:
let
  # Load hardware facts (generated by nixos-facter)
  facterReport = lib.importJSON ./facter.json;

  # Detect hardware characteristics
  cpuVendor = facterReport.cpu.vendor or "unknown";
  gpuVendor = lib.head (lib.mapAttrsToList
    (n: v: v.vendor)
    (facterReport.gpus or {}));
  totalMemoryGB = facterReport.memory.total / (1024 * 1024 * 1024);

  # Determine profile based on hardware
  hardwareProfile =
    if cpuVendor == "GenuineIntel" && totalMemoryGB < 8
    then "low-power"
    else if gpuVendor == "NVIDIA Corporation"
    then "gaming"
    else if totalMemoryGB >= 32
    then "workstation"
    else "standard";
in
{
  flake.nixosModules.auto-hardware = {
    imports = [
      config.flake.nixosModules.${hardwareProfile}
    ];

    # Apply detected settings
    boot.kernelPackages =
      if cpuVendor == "AuthenticAMD"
      then pkgs.linuxPackages_zen
      else pkgs.linuxPackages_latest;

    # Scale ZFS ARC based on memory
    boot.zfs.arc.max = lib.mkIf (totalMemoryGB > 16)
      (toString (totalMemoryGB / 2 * 1024 * 1024 * 1024));
  };
}
```

### Hardware Abstraction Layer

Create abstractions for hardware variations:

```nix
# modules/hardware/display-profiles.nix
{ config, lib, ... }:
{
  options.flake.hardware.display = {
    profile = lib.mkOption {
      type = lib.types.enum [ "laptop" "desktop-1080p" "desktop-4k" "multi-monitor" ];
      default = "desktop-1080p";
    };
  };

  config.flake.nixosModules.base = { config, lib, pkgs, ... }: {
    services.xserver.dpi =
      if config.flake.hardware.display.profile == "desktop-4k" then 144
      else if config.flake.hardware.display.profile == "laptop" then 120
      else 96;

    # Scaling for different displays
    environment.variables = lib.mkIf (config.flake.hardware.display.profile == "desktop-4k") {
      GDK_SCALE = "1.5";
      QT_SCALE_FACTOR = "1.5";
    };

    # Multi-monitor setup
    services.autorandr = lib.mkIf (config.flake.hardware.display.profile == "multi-monitor") {
      enable = true;
      profiles = {
        default = {
          config = {
            DP-1 = {
              enable = true;
              mode = "3840x2160";
              position = "0x0";
              rate = "60.00";
            };
            DP-2 = {
              enable = true;
              mode = "3840x2160";
              position = "3840x0";
              rate = "60.00";
            };
          };
        };
      };
    };
  };
}
```

## User-Specific Configurations

### Multi-User System Pattern

Manage multiple users with different requirements:

```nix
# modules/users/registry.nix
{ config, lib, ... }:
let
  userRegistry = {
    alice = {
      uid = 1000;
      groups = [ "wheel" "docker" "libvirtd" ];
      shell = "zsh";
      role = "developer";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlice alice@laptop"
      ];
    };
    bob = {
      uid = 1001;
      groups = [ "users" "audio" "video" ];
      shell = "bash";
      role = "designer";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBob bob@desktop"
      ];
    };
    carol = {
      uid = 1002;
      groups = [ "wheel" ];
      shell = "fish";
      role = "admin";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICarol carol@server"
      ];
    };
  };
in
{
  # Generate user configurations
  flake.nixosModules.base = { pkgs, ... }: {
    users.users = lib.mapAttrs (username: userCfg: {
      isNormalUser = true;
      uid = userCfg.uid;
      extraGroups = userCfg.groups;
      shell = pkgs.${userCfg.shell};
      openssh.authorizedKeys.keys = userCfg.sshKeys;
    }) userRegistry;
  };

  # Generate Home Manager configurations
  flake.homeManagerModules = lib.mapAttrs (username: userCfg: {
    imports = [
      config.flake.homeManagerModules.base
      config.flake.homeManagerModules.${userCfg.role}
    ];

    home.username = username;
    home.homeDirectory = "/home/${username}";
  }) userRegistry;

  # Role-specific configurations
  flake.homeManagerModules.developer = { pkgs, ... }: {
    programs.vscode.enable = true;
    programs.direnv.enable = true;
    home.packages = with pkgs; [
      docker-compose
      kubectl
      terraform
    ];
  };

  flake.homeManagerModules.designer = { pkgs, ... }: {
    home.packages = with pkgs; [
      inkscape
      gimp
      blender
    ];
  };
}
```

### Per-User Secret Management

Handle user-specific secrets:

```nix
# modules/users/secrets.nix
{ config, lib, ... }:
{
  options.flake.userSecrets = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        passwordHash = lib.mkOption {
          type = lib.types.str;
          description = "Hashed password for the user";
        };
        wireguardKey = lib.mkOption {
          type = lib.types.path;
          description = "Path to WireGuard private key";
        };
        gpgKey = lib.mkOption {
          type = lib.types.path;
          description = "Path to GPG private key";
        };
      };
    });
  };

  config = {
    # Define secrets
    flake.userSecrets = {
      alice = {
        passwordHash = "$6$rounds=100000$...";  # mkpasswd -m sha-512
        wireguardKey = ./secrets/alice-wg.key;
        gpgKey = ./secrets/alice-gpg.asc;
      };
    };

    # Apply secrets
    flake.nixosModules.base = { config, ... }: {
      users.users = lib.mapAttrs (username: secrets: {
        hashedPassword = secrets.passwordHash;
      }) config.flake.userSecrets;
    };

    # User-specific WireGuard
    flake.nixosModules.vpn = { config, ... }: {
      networking.wireguard.interfaces = lib.mapAttrs (username: secrets: {
        wg0 = {
          privateKeyFile = secrets.wireguardKey;
          ips = [ "10.100.0.${toString config.users.users.${username}.uid}/24" ];
        };
      }) config.flake.userSecrets;
    };
  };
}
```

## CI/CD Integration

### Automated Testing

Setup comprehensive CI/CD:

```nix
# modules/meta/ci.nix
{ config, lib, inputs, ... }:
{
  # Generate GitHub Actions workflow
  flake.files."${config.flake.root}/.github/workflows/ci.yml" = {
    text = lib.generators.toYAML {} {
      name = "CI";
      on = {
        push.branches = [ "main" ];
        pull_request.branches = [ "main" ];
      };

      jobs = {
        check = {
          runs-on = "ubuntu-latest";
          strategy = {
            matrix = {
              check = lib.attrNames config.flake.checks.x86_64-linux;
            };
            fail-fast = false;
          };

          steps = [
            { uses = "actions/checkout@v3"; }
            {
              uses = "cachix/install-nix-action@v22";
              with = {
                extra_nix_config = ''
                  experimental-features = nix-command flakes pipe-operators
                  accept-flake-config = true
                '';
              };
            }
            {
              uses = "cachix/cachix-action@v12";
              with = {
                name = "my-cache";
                authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
              };
            }
            {
              name = "Build check";
              run = ''
                nix build .#checks.x86_64-linux.\${{ matrix.check }} \
                  --extra-experimental-features pipe-operators \
                  --print-build-logs
              '';
            }
          ];
        };

        deploy = {
          needs = [ "check" ];
          runs-on = "ubuntu-latest";
          if = "github.ref == 'refs/heads/main'";

          steps = [
            { uses = "actions/checkout@v3"; }
            {
              name = "Deploy to production";
              run = ''
                nix run .#deploy-all-prod \
                  --extra-experimental-features pipe-operators
              '';
              env = {
                SSH_PRIVATE_KEY = "\${{ secrets.DEPLOY_SSH_KEY }}";
              };
            }
          ];
        };
      };
    };
  };
}
```

### Continuous Deployment

Implement GitOps-style deployment:

```nix
# modules/deployment/gitops.nix
{ config, lib, ... }:
{
  # Auto-update systems
  flake.nixosModules.gitops = { config, pkgs, ... }: {
    systemd.services.nixos-update = {
      description = "NixOS GitOps Update";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "update-system" ''
          #!/usr/bin/env bash
          set -euo pipefail

          cd /etc/nixos
          git pull origin main

          nixos-rebuild switch \
            --flake .#${config.networking.hostName} \
            --extra-experimental-features pipe-operators
        '';
      };
    };

    systemd.timers.nixos-update = {
      description = "NixOS GitOps Update Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 02:00:00";  # Daily at 2 AM
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };
  };
}
```

## Performance Optimization

### Evaluation Performance

Optimize module evaluation:

```nix
# modules/performance/evaluation.nix
{ config, lib, ... }:
{
  # Use lazy evaluation effectively
  flake.nixosModules.optimized = { config, lib, pkgs, ... }:
  let
    # Expensive computations only when needed
    expensivePackageList = lib.mkIf config.services.xserver.enable
      (import ./heavy-package-computation.nix { inherit pkgs; });
  in {
    # Use mkDefault for overridable values
    services.journald.extraConfig = lib.mkDefault ''
      SystemMaxUse=1G
      RuntimeMaxUse=100M
    '';

    # Lazy attribute sets
    environment.systemPackages = lib.mkMerge [
      (lib.mkIf config.services.xserver.enable expensivePackageList)
      [ pkgs.vim pkgs.git ]  # Always included
    ];

    # Avoid recursive dependencies
    networking.hostName = lib.mkDefault "nixos";  # Not config.networking.hostName
  };
}
```

### Build Performance

Optimize build times:

```nix
# modules/performance/build.nix
{ config, lib, ... }:
{
  flake.nixosModules.base = { config, pkgs, ... }: {
    # Parallel building
    nix.settings = {
      max-jobs = "auto";
      cores = 0;  # Use all cores

      # Use binary caches
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      # Optimize store automatically
      auto-optimise-store = true;

      # Garbage collection
      min-free = lib.mkDefault (1024 * 1024 * 1024);  # 1GB
      max-free = lib.mkDefault (10 * 1024 * 1024 * 1024);  # 10GB
    };

    # Periodic optimization
    systemd.services.nix-optimise = {
      description = "Nix Store Optimization";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.nix}/bin/nix-store --optimise";
      };
    };

    systemd.timers.nix-optimise = {
      description = "Nix Store Optimization Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };
}
```

### Memory Optimization

Reduce memory usage:

```nix
# modules/performance/memory.nix
{ config, lib, ... }:
{
  flake.nixosModules.memory-optimized = {
    # Tune kernel parameters
    boot.kernel.sysctl = {
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
      "vm.dirty_ratio" = 5;
      "vm.dirty_background_ratio" = 2;
    };

    # Use zram for swap
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };

    # Optimize systemd
    systemd.services = {
      "systemd-journald".serviceConfig = {
        MemoryMax = "100M";
        MemoryHigh = "80M";
      };
    };

    # Disable unnecessary services
    services.avahi.enable = lib.mkDefault false;
    services.printing.enable = lib.mkDefault false;
  };
}
```

## Security Best Practices

### Security Hardening

Implement security layers:

```nix
# modules/security/hardening.nix
{ config, lib, ... }:
{
  flake.nixosModules.hardened = { config, lib, pkgs, ... }: {
    # Kernel hardening
    boot.kernelPackages = pkgs.linuxPackages_hardened;
    boot.kernel.sysctl = {
      # Network hardening
      "net.ipv4.tcp_syncookies" = 1;
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # Kernel hardening
      "kernel.kptr_restrict" = 2;
      "kernel.yama.ptrace_scope" = 1;
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;
      "kernel.ftrace_enabled" = false;
    };

    # Security modules
    security = {
      apparmor.enable = true;
      audit.enable = true;
      auditd.enable = true;

      sudo = {
        wheelNeedsPassword = true;
        execWheelOnly = true;
      };
    };

    # Service hardening
    systemd.services = lib.mapAttrs (name: service: {
      serviceConfig = {
        NoNewPrivileges = lib.mkDefault true;
        PrivateTmp = lib.mkDefault true;
        ProtectSystem = lib.mkDefault "strict";
        ProtectHome = lib.mkDefault true;
        ProtectKernelTunables = lib.mkDefault true;
        ProtectKernelModules = lib.mkDefault true;
        ProtectControlGroups = lib.mkDefault true;
        RestrictAddressFamilies = lib.mkDefault [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        RestrictNamespaces = lib.mkDefault true;
        LockPersonality = lib.mkDefault true;
        MemoryDenyWriteExecute = lib.mkDefault true;
        RestrictRealtime = lib.mkDefault true;
        RestrictSUIDSGID = lib.mkDefault true;
        SystemCallArchitectures = lib.mkDefault "native";
      };
    }) config.systemd.services;
  };
}
```

### Secrets Management

Implement secure secrets handling:

```nix
# modules/security/secrets.nix
{ config, lib, inputs, ... }:
{
  imports = [ inputs.agenix.nixosModules.default ];

  options.flake.secrets = {
    path = lib.mkOption {
      type = lib.types.path;
      default = ./secrets;
      description = "Path to encrypted secrets";
    };
  };

  config = {
    # Define secrets
    age.secrets = {
      wireguard-private = {
        file = "${config.flake.secrets.path}/wireguard.age";
        owner = "systemd-network";
        group = "systemd-network";
      };

      database-password = {
        file = "${config.flake.secrets.path}/database.age";
        owner = "postgres";
        group = "postgres";
        mode = "0400";
      };

      ssl-cert = {
        file = "${config.flake.secrets.path}/ssl-cert.age";
        owner = "nginx";
        group = "nginx";
        path = "/var/lib/ssl/cert.pem";
      };
    };

    # Use secrets in services
    flake.nixosModules.services = {
      services.postgresql.authentication = ''
        local all all peer
        host all all 127.0.0.1/32 md5
      '';

      systemd.services.postgresql.serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/cat ${config.age.secrets.database-password.path}";
      };
    };
  };
}
```

## Module Testing Strategies

### Unit Testing Modules

Test individual modules:

```nix
# modules/tests/unit.nix
{ config, lib, pkgs, ... }:
{
  # Define test cases
  flake.checks = lib.mapAttrs (name: test:
    pkgs.nixosTest {
      name = "module-test-${name}";
      nodes.machine = {
        imports = [ test.module ];
        # Test-specific config
      };
      testScript = test.script;
    }
  ) {
    nginx = {
      module = config.flake.nixosModules.webserver;
      script = ''
        machine.wait_for_unit("nginx.service")
        machine.succeed("curl http://localhost")
      '';
    };

    postgresql = {
      module = config.flake.nixosModules.database;
      script = ''
        machine.wait_for_unit("postgresql.service")
        machine.succeed("sudo -u postgres psql -c 'SELECT 1'")
      '';
    };
  };
}
```

### Integration Testing

Test module combinations:

```nix
# modules/tests/integration.nix
{ config, lib, pkgs, ... }:
{
  flake.checks.integration = pkgs.nixosTest {
    name = "integration-test";

    nodes = {
      webserver = {
        imports = with config.flake.nixosModules; [
          base
          webserver
          monitoring
        ];
      };

      database = {
        imports = with config.flake.nixosModules; [
          base
          database
          backup
        ];
      };

      client = {
        imports = [ config.flake.nixosModules.base ];
      };
    };

    testScript = ''
      # Start all nodes
      webserver.start()
      database.start()
      client.start()

      # Test connectivity
      client.wait_for_unit("network.target")
      client.succeed("ping -c 1 webserver")
      client.succeed("ping -c 1 database")

      # Test services
      webserver.wait_for_unit("nginx.service")
      database.wait_for_unit("postgresql.service")

      # Test integration
      client.succeed("curl http://webserver")
      webserver.succeed("psql -h database -U testuser -c 'SELECT 1'")
    '';
  };
}
```

## Advanced Module Patterns

### Module Factories

Create modules dynamically:

```nix
# modules/factories/microservice.nix
{ config, lib, ... }:
let
  mkMicroservice = { name, port, image, environment ? {} }: {
    virtualisation.oci-containers.containers.${name} = {
      inherit image environment;
      ports = [ "${toString port}:${toString port}" ];
      autoStart = true;
    };

    services.nginx.virtualHosts."${name}.local" = {
      locations."/" = {
        proxyPass = "http://localhost:${toString port}";
        proxyWebsockets = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ port ];
  };
in
{
  # Generate microservice modules
  flake.nixosModules = {
    api-gateway = mkMicroservice {
      name = "api-gateway";
      port = 8080;
      image = "company/api-gateway:latest";
      environment.LOG_LEVEL = "info";
    };

    auth-service = mkMicroservice {
      name = "auth-service";
      port = 8081;
      image = "company/auth-service:latest";
    };

    user-service = mkMicroservice {
      name = "user-service";
      port = 8082;
      image = "company/user-service:latest";
    };
  };
}
```

### Module Composition Helpers

Create composition utilities:

```nix
# modules/lib/compose.nix
{ lib, ... }:
{
  flake.lib.compose = {
    # Merge multiple modules with conflict resolution
    mergeModules = modules: lib.mkMerge (
      map (m: lib.mkDefault m) modules
    );

    # Conditional module inclusion
    includeIf = condition: module:
      lib.mkIf condition module;

    # Override with priority
    override = priority: module:
      lib.mkOverride priority module;

    # Module with metadata
    withMeta = meta: module: module // { inherit meta; };
  };
}
```

## Summary of Best Practices

1. **Think in Layers**: Build from general to specific
2. **Compose, Don't Inherit**: Use module composition over deep inheritance
3. **Lazy by Default**: Use lazy evaluation for performance
4. **Test Everything**: Unit and integration tests for all modules
5. **Security First**: Apply security hardening systematically
6. **Document Patterns**: Document your specific patterns and decisions
7. **Version Control**: Track all changes with meaningful commits
8. **Automate Deployment**: Use CI/CD for consistent deployments
9. **Monitor and Optimize**: Track performance and optimize bottlenecks
10. **Evolve Gradually**: The pattern grows with your needs

The dendritic pattern's power comes from its flexibility and organic growth. These advanced patterns show how sophisticated configurations can emerge from simple, composable modules.
