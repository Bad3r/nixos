# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This directory contains the complete NixOS documentation converted to markdown format. The documentation is organized into 460 numbered files covering all aspects of NixOS configuration, services, and system management.

## File Organization

Files are numbered sequentially from `001_` to `460_` with descriptive names:
- **001-050**: Core NixOS concepts (installation, configuration syntax, package management)
- **051-100**: System services and networking
- **100-300**: Individual service documentation (web services, databases, etc.)
- **300-400**: Hardware support, system management, and specialized configurations  
- **400-460**: Development topics (writing modules, tests, documentation)

## Documentation Sections

### Installation & Getting Started (001-018)
- NixOS version information
- Obtaining and installing NixOS
- Installation methods (graphical & manual)
- Building custom ISOs and images
- Boot configuration

### Core Configuration (019-032)
- Configuration syntax and NixOS configuration file
- Abstractions and modularity
- Package management (declarative & ad-hoc)
- User and group management
- File systems (standard, LUKS-encrypted, SSHFS, overlayfs)

### Desktop Environments & Graphics (033-049)
- X Window System configuration
- Wayland
- GPU acceleration (OpenCL, Vulkan, VA-API)
- Graphics drivers (Intel, NVIDIA)
- Desktop environments (Xfce, GNOME, Pantheon)
- Themes and customization

### Networking & System (050-065)
- Network configuration and NetworkManager
- SSH access and configuration
- IPv4/IPv6 configuration
- Firewall and wireless networks
- Linux kernel configuration
- Custom kernel modules and ZFS

### Services - Web Applications (082-168)
- Web services: Nextcloud, Discourse, Lemmy, Akkoma, Pleroma
- Analytics: Plausible, Matomo
- Media: Castopod, Jellyfin, Pict-rs
- Collaboration: Jitsi Meet, Matrix/Synapse
- Development: Gitea/Forgejo, GitLab, YouTrack
- File sharing: Pingvin Share, FileSender

### Services - Infrastructure (169-262)
- Databases: PostgreSQL, FoundationDB
- Monitoring: Prometheus exporters, Goss, Cert Spotter
- Networking: DNS servers, Pi-hole, Yggdrasil, Netbird
- Messaging: MQTT (Mosquitto), XMPP (Prosody)
- Backup: BorgBackup, Litestream
- Task management: Taskserver

### Services - Matrix Ecosystem (279-295)
- Synapse homeserver
- Element web client
- Moderation tools (Mjolnir, Draupnir)
- Bridges (mautrix-whatsapp, mautrix-signal)
- Bot framework (maubot)

### Hardware & System Tools (299-378)
- Hardware wallets (Trezor, Digital Bitbox)
- Display configuration and EDID management
- Input methods (IBus, Fcitx5, etc.)
- System profiles (minimal, hardened, graphical)
- Emacs configuration

### System Management (379-418)
- Service management with systemd
- Container management
- Boot entries and troubleshooting
- Nix store maintenance
- System state and recovery

### Development & Advanced Topics (419-460)
- Writing NixOS modules
- NixOS test framework
- Building documentation
- Modular services
- Development mode features
- Command-line tools and debugging

## Common Commands

### Search Documentation

```bash
# Search for a specific topic
grep -i "postgresql" *.md

# Find files about a service
ls | grep -i "matrix"

# Search file contents with context
grep -B2 -A2 "services.nginx" *.md
```

### Navigate by Topic

```bash
# List all service documentation
ls | grep -E "^[0-9]{3}_(akkoma|discourse|gitlab|lemmy|matrix|nextcloud|postgresql)"

# Find system configuration topics
ls | grep -E "(configuration|package|user|network|kernel)"

# Locate troubleshooting guides
ls | grep -i "troubleshoot"
```

### Quick Access by Section

```bash
# Installation guides (001-018)
ls 00[12]*.md

# Core configuration (019-032)
ls 0[23]*.md

# Desktop/graphics (033-049)
ls 0[34]*.md | grep -E "(wayland|x_window|gpu|desktop)"

# Networking (050-065)
ls 05*.md 06*.md | head -15

# Web services (082-168)
ls {08,09,10,11,12,13,14,15,16}*.md | grep -E "(nextcloud|discourse|gitlab)"

# Matrix ecosystem (279-295)
ls 2[89]*.md | grep -i "matrix\|mautrix\|synapse"

# Development topics (419-460)
ls 4[0-6]*.md
```

## Key Documentation Files

- `019_configuration_syntax.md` - NixOS configuration language basics
- `023_package_management.md` - Managing packages in NixOS
- `050_networking.md` - Network configuration
- `321_postgresql.md` - PostgreSQL database setup
- `413_troubleshooting.md` - General troubleshooting guide
- `420_writing_nixos_modules.md` - Module development

## Usage Notes

- Files contain converted HTML-to-markdown documentation from the official NixOS manual
- Internal links may reference section anchors (e.g., `#sec-configuration-file`)
- Service documentation typically includes: basic usage, configuration, and examples
- Some files reference external resources or upstream documentation