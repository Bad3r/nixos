# Documentation Index

## Onboarding

- [onboarding.md](onboarding.md)
  - Project overview, repository layers, key concepts, the guided reading path, and the complexity hotspots.

## Architecture

- [architecture/README.md](architecture/README.md)
  - Index and reading order for Dendritic Pattern architecture documentation with quick links to common tasks.
- [architecture/01-pattern-overview.md](architecture/01-pattern-overview.md)
  - Explains the Dendritic Pattern's automatic module discovery, aggregator namespaces, and organic configuration growth.
- [architecture/02-module-authoring.md](architecture/02-module-authoring.md)
  - Covers file placement conventions, common pitfalls, and the two-context problem.
- [architecture/02-module-authoring-patterns.md](architecture/02-module-authoring-patterns.md)
  - Module shapes with and without `pkgs`, multi-namespace modules, namespace extensions, and host modules.
- [architecture/02-module-authoring-arguments.md](architecture/02-module-authoring-arguments.md)
  - The `metaOwner`, `secretsRoot`, `inputs`, and `hostName` arguments, their Home Manager counterparts, and the app helpers.
- [architecture/03-nixos-modules.md](architecture/03-nixos-modules.md)
  - Documents the flake.nixosModules namespace, app registry helpers (hasApp, getApp, getApps), overlay packages, and unfree packages.
- [architecture/03-nixos-modules-namespaces.md](architecture/03-nixos-modules-namespaces.md)
  - The `flake.lib` sub-namespaces and the `flake.csec` feature modules.
- [architecture/04-home-manager.md](architecture/04-home-manager.md)
  - Covers the flake.homeManagerModules namespace, app loading mechanism, and secrets integration for user configuration.
- [architecture/05-host-composition.md](architecture/05-host-composition.md)
  - Explains host definition, shared imports, host-conditional policy, app and Home Manager wiring, and validation.
- [architecture/host-file-inventory.md](architecture/host-file-inventory.md)
  - Maps host-owned files to their responsibilities and separates them from shared host composition.
- [architecture/06-reference.md](architecture/06-reference.md)
  - Quick reference for validation commands, credential scanning scope, introspection via REPL, dev shell helpers, and glossary of terms.
- [architecture/07-troubleshooting.md](architecture/07-troubleshooting.md)
  - Symptoms that come up while working in the repository, each paired with its resolution.

## Drafts

- [drafts/android-emulator-network-plan.md](drafts/android-emulator-network-plan.md)
  - Draft plan for Android emulator network interception setup with mitmproxy, KVM acceleration, and CA management.
- [drafts/chromium-webapps-plan-1-salvage.md](drafts/chromium-webapps-plan-1-salvage.md)
  - Phase 1 of the Chromium web-app migration: rescue the compgen and statix fixes stranded in PR #435, then close it.
- [drafts/chromium-webapps-plan-2-remove-firefoxpwa.md](drafts/chromium-webapps-plan-2-remove-firefoxpwa.md)
  - Phase 2 of the Chromium web-app migration: delete the Firefox PWA subsystem and unwire every reference to it.
- [drafts/chromium-webapps-plan-3-implement.md](drafts/chromium-webapps-plan-3-implement.md)
  - Phase 3 of the Chromium web-app migration: the `programs.webapps` module on brave-origin, plus the decisions table, the fact table, and the self-review for the series.
- [drafts/duplicati-r2-readonly-mount-investigation.md](drafts/duplicati-r2-readonly-mount-investigation.md)
  - Investigation into a read-only mount for encrypted R2 backup archives (issue #204).

## Guides

- [guides/README.md](guides/README.md)
  - Index of style guides, coding standards, and how-to documentation.
- [guides/apps-module-style-guide.md](guides/apps-module-style-guide.md)
  - File layout, module body, namespace selection, and the steps for adding a `modules/apps/` module.
- [guides/apps-module-header.md](guides/apps-module-header.md)
  - Header block fields, sections, option documentation, and the sources behind each field.
- [guides/apps-module-package-sources.md](guides/apps-module-package-sources.md)
  - Package options for nixpkgs, external flake input, and Python packages.
- [guides/apps-module-registry.md](guides/apps-module-registry.md)
  - Baseline and host rows, prerequisite rows, the registry checks, and which module installs a package.
- [guides/apps-module-home-manager.md](guides/apps-module-home-manager.md)
  - Home Manager app modules gated on the NixOS row, package handling, loading, and theming.
- [guides/custom-packages-style-guide.md](guides/custom-packages-style-guide.md)
  - When to create a package under `packages/`, file structure, meta fields, app modules, and validation.
- [guides/custom-packages-source-builds.md](guides/custom-packages-source-builds.md)
  - Rust, Go, and Python package templates.
- [guides/custom-packages-binaries-and-scripts.md](guides/custom-packages-binaries-and-scripts.md)
  - Binary download and shell wrapper package templates.
- [guides/custom-packages-overlays.md](guides/custom-packages-overlays.md)
  - Exposing an in-tree package as `pkgs.<name>` through a gated overlay, or as a flake output.
- [guides/custom-packages-hashes.md](guides/custom-packages-hashes.md)
  - Source, cargo, and vendor hash workflows, updater hash helpers, and mismatch recovery.
- [guides/github-deployments.md](guides/github-deployments.md)
  - Using GitHub's Deployments API via gh CLI for tracking deployments (metadata only, not actual deployment).
- [guides/host-onboarding.md](guides/host-onboarding.md)
  - Runbook for adding a NixOS host: registry entry, per-host module set, policy flags, validation ladder, label, and docs rosters.
- [guides/host-onboarding-secrets.md](guides/host-onboarding-secrets.md)
  - Age identity, secrets submodule, backup manifest, SSH host key pin, and primary handoff for a new host.
- [guides/nix-debugging-manual.md](guides/nix-debugging-manual.md)
  - Debugging techniques for Nix expressions, NixOS modules, and Home Manager including REPL, tracing, and common errors.
- [guides/nix-null-coercion.md](guides/nix-null-coercion.md)
  - Diagnosing and repairing null coercion failures in Nix module evaluation.
- [guides/qbittorrent-web-ui-setup.md](guides/qbittorrent-web-ui-setup.md)
  - Setting up the qBittorrent Web UI, with optional desktop profile import and Songbird as the host example.
- [guides/stylix-integration.md](guides/stylix-integration.md)
  - Stylix theming integration covering NixOS vs Home Manager targets, autoEnable behavior, and module author rules.
- [guides/stylix-troubleshooting.md](guides/stylix-troubleshooting.md)
  - Stylix pitfalls, from Home Manager targets set in NixOS modules to `_module.check`, and the debugging commands.
- [guides/tray-icon-overrides.md](guides/tray-icon-overrides.md)
  - Package-level tray icon overrides for ProtonVPN, NormCap, Teams for Linux, and udiskie, and the snixembed bridge patches.
- [guides/tray-icon-theming.md](guides/tray-icon-theming.md)
  - i3/i3bar tray icon theming guide with protocol classification, runtime verification, and remediation workflow.

## NixOS manual

- [NixOS manual (unstable)](https://nixos.org/manual/nixos/unstable/)
  - Upstream NixOS manual for the unstable channel.

## Networking

- [networking/README.md](networking/README.md)
  - NetworkManager MAC-address policies and temporary macchanger commands.
- [networking/interface-names.md](networking/interface-names.md)
  - Pinning interface names under `net.ifnames=0` and narrowing alternative names without a pin.
- [networking/link-policy.md](networking/link-policy.md)
  - systemd-udevd `.link` address policies, device matching, and when a change applies.
- [networking/stable-mac-rekey.md](networking/stable-mac-rekey.md)
  - Re-keying DHCP reservations and MAC allowlists after the `"stable"` cutover and after profile, name, or identity changes.
- [networking/workload-services.md](networking/workload-services.md)
  - Declared containers on rootful Podman: networks, user namespaces, firewall ownership, published ports, and DNS.
- [networking/workloads.md](networking/workloads.md)
  - Workload bridge networks: table ownership, declaring a network, egress modes, and verification.
- [networking/workload-links.md](networking/workload-links.md)
  - Host services, links from guests to host services and other guests, and gateway proxies.

## Packaging

- [packaging/javascript-packages.md](packaging/javascript-packages.md)
  - Packaging npm, pnpm, and bun applications in NixOS including monorepos, native modules, and Electron apps.

## Cybersecurity

- [csec/toolkit.md](csec/toolkit.md)
  - Catalog of cybersecurity-relevant apps managed by this configuration covering recon, web testing, credential attacks, RE, forensics, and dual-use utilities.
- [csec/toolkit/network-reconnaissance-enumeration.md](csec/toolkit/network-reconnaissance-enumeration.md)
  - DNS enumeration, asset discovery, and service reconnaissance tools.
- [csec/toolkit/active-directory-smb-enumeration.md](csec/toolkit/active-directory-smb-enumeration.md)
  - Active Directory and SMB discovery and assessment utilities.
- [csec/toolkit/web-application-testing-proxies.md](csec/toolkit/web-application-testing-proxies.md)
  - Web application scanners, proxies, fuzzers, and WebSocket clients.
- [csec/toolkit/credential-attacks-wordlists.md](csec/toolkit/credential-attacks-wordlists.md)
  - Password auditing tools and credential attack wordlists.
- [csec/toolkit/wireless-auditing.md](csec/toolkit/wireless-auditing.md)
  - Wireless network discovery and security assessment utilities.
- [csec/toolkit/exploitation-frameworks.md](csec/toolkit/exploitation-frameworks.md)
  - Exploitation frameworks and payload development tools.
- [csec/toolkit/reverse-engineering-dynamic-analysis.md](csec/toolkit/reverse-engineering-dynamic-analysis.md)
  - Binary analysis, decompilation, and dynamic instrumentation tools.
- [csec/toolkit/javascript-reversing-source-recovery.md](csec/toolkit/javascript-reversing-source-recovery.md)
  - JavaScript deobfuscation, source recovery, and analysis utilities.
- [csec/toolkit/anonymity-vpn-tunneling.md](csec/toolkit/anonymity-vpn-tunneling.md)
  - Anonymity networks, VPN clients, and tunneling tools.
- [csec/toolkit/forensics-recovery-imaging.md](csec/toolkit/forensics-recovery-imaging.md)
  - Forensic collection, recovery, and imaging utilities.
- [csec/toolkit/auditing-vulnerability-assessment.md](csec/toolkit/auditing-vulnerability-assessment.md)
  - Host and infrastructure auditing and vulnerability assessment tools.
- [csec/toolkit/cryptography-secrets-credential-management.md](csec/toolkit/cryptography-secrets-credential-management.md)
  - Cryptography, secret handling, and credential management utilities.
- [csec/toolkit/disk-storage-inspection.md](csec/toolkit/disk-storage-inspection.md)
  - Disk and storage inspection tools.
- [csec/toolkit/document-pdf-analysis.md](csec/toolkit/document-pdf-analysis.md)
  - Document and PDF inspection and extraction utilities.
- [csec/toolkit/database-clients.md](csec/toolkit/database-clients.md)
  - Database clients for service testing and artifact inspection.
- [csec/toolkit/traffic-capture-network-diagnostics.md](csec/toolkit/traffic-capture-network-diagnostics.md)
  - Packet capture, socket relays, and network diagnostics tools.
- [csec/toolkit/system-internals-incident-response.md](csec/toolkit/system-internals-incident-response.md)
  - System inspection and incident response utilities.
- [csec/toolkit/archive-compression-analysis.md](csec/toolkit/archive-compression-analysis.md)
  - Archive and compression analysis tools.
- [csec/toolkit/qr-encoded-payload-handling.md](csec/toolkit/qr-encoded-payload-handling.md)
  - QR code and encoded payload handling utilities.
- [csec/toolkit/containers-virtualization-cloud-labs.md](csec/toolkit/containers-virtualization-cloud-labs.md)
  - Container, virtualization, and cloud lab tools.
- [csec/toolkit/privacy-focused-research-browsers.md](csec/toolkit/privacy-focused-research-browsers.md)
  - Privacy-focused and research web browsers.
- [csec/toolkit/browser-api-automation.md](csec/toolkit/browser-api-automation.md)
  - Browser and API automation utilities.
- [csec/toolkit/remote-access.md](csec/toolkit/remote-access.md)
  - Remote shell and desktop access clients.
- [csec/glossary.md](csec/glossary.md)
  - Reference glossary for cybersecurity and software-engineering acronyms and concepts.
- [csec/additional-tools-reference.md](csec/additional-tools-reference.md)
  - Reference catalog of pentesting tools available via `nix run`/`nix shell` that complement the active toolkit, grouped by AD, recon, web testing, credential attacks, wireless, RE, forensics, stego, SAST, cloud, and pivoting.
- [csec/additional-tools-runtime-status.md](csec/additional-tools-runtime-status.md)
  - Smoke-test report for the additional-tools reference; records which entries launched cleanly on the active flake pin and which failed with build, attribute, or invocation issues.
- [csec/protocol-aware-firewall.md](csec/protocol-aware-firewall.md)
  - Packet-signature and conntrack-mark techniques for detecting and blocking application protocol mismatches on a firewall port, with iptables and nftables examples.

## Reference

- [reference/binary-cache-coverage.md](reference/binary-cache-coverage.md)
  - Operator surface for serving custom derivations from a binary cache, its substituter wiring, build surface, and CI publisher.
- [reference/binary-cache-coverage-policy.md](reference/binary-cache-coverage-policy.md)
  - License posture and evaluated inventory for published binary-cache roots.
- [reference/binary-cache-coverage-operations.md](reference/binary-cache-coverage-operations.md)
  - Cachix setup, publisher verification, and known binary-cache coverage gaps.
- [reference/binary-cache-coverage-extension.md](reference/binary-cache-coverage-extension.md)
  - Rules for adding derivations to the published binary-cache roots.
- [reference/cache-coverage.md](reference/cache-coverage.md)
  - Per-host report of closure derivations that would compile locally despite a substitutable nixpkgs equivalent.
- [reference/fork-sync-automation.md](reference/fork-sync-automation.md)
  - Scheduled upstream sync workflow installed in each flake-input fork, its conflict behavior, and the installer for adding new forks.
- [reference/github-labels.md](reference/github-labels.md)
  - GitHub label taxonomy, application rules, and label-family reference for issues and pull requests.
- [reference/iphone.md](reference/iphone.md)
  - iPhone pairing, AFC and PTP file transfer, encrypted backups, and USB tethering through the usbmuxd/libimobiledevice stack.
- [reference/local-mirrors.md](reference/local-mirrors.md)
  - Local repository mirrors under `$LOCAL_MIRRORS`: where a spec lands, adding a mirror, and the provisioned mirror root.
- [reference/local-mirrors-sync.md](reference/local-mirrors-sync.md)
  - What `git-mirror.service` does to each mirror, how local work survives a sync, and the maintenance run after it.
- [reference/local-mirrors-docs.md](reference/local-mirrors-docs.md)
  - Firefox source docs and Python documentation trees published from the mirrors after each sync.
- [reference/local-mirrors-troubleshooting.md](reference/local-mirrors-troubleshooting.md)
  - Failed mirror syncs and docs runs, by the line they log.
- [reference/mcp-tools.md](reference/mcp-tools.md)
  - Quick reference for available MCP tools including context7, cfdocs, cfbrowser, and deepwiki.
- [reference/secrets-guard.md](reference/secrets-guard.md)
  - Scan that stops `path:` references from copying untracked secrets into the store: what it matches, how to override a hit, which trees it owns, and why it aborts.
- [reference/stash-prune.md](reference/stash-prune.md)
  - Age-based stash pruning, the archive-before-drop recoverability guarantee, archive retention sweeps, and recovery paths.
- [reference/useful-commands.md](reference/useful-commands.md)
  - Collection of handy general-purpose CLI commands not tied to NixOS or this repository.
- [reference/worktree-prune.md](reference/worktree-prune.md)
  - Pruning of local branches with gone upstreams and their worktrees, the scheduled cleanup timer, safety guarantees, and recovery paths.
- [reference/zsh.md](reference/zsh.md)
  - Layout of the owner's Home Manager zsh module, its startup order, where each kind of change goes, and its flake check.

## Security

- [security/owner-group-privileges.md](security/owner-group-privileges.md)
  - Security-relevant access granted by owner group membership.
- [security/owner-disk-group.md](security/owner-disk-group.md)
  - Raw storage access and the filtered diagnostic wrappers the owner's `disk` group grants.
- [security/owner-optional-groups.md](security/owner-optional-groups.md)
  - Groups the owner profile leaves unassigned and optional device groups, with their security impact.
- [security/owner-no-sudo-operations.md](security/owner-no-sudo-operations.md)
  - Configuration-managed operations available to the owner user without a sudo password.
- [security/owner-no-sudo-storage.md](security/owner-no-sudo-storage.md)
  - Storage inventory and health diagnostics without a sudo password, and the capability wrappers that grant them.
- [security/owner-no-sudo-nvme.md](security/owner-no-sudo-nvme.md)
  - Which `nvme` subcommands keep the wrapper's storage capability, which clear it, and why each exclusion exists.
- [security/owner-no-sudo-sed.md](security/owner-no-sudo-sed.md)
  - Opal self-encrypting drive queries without a sudo password, and the state-changing actions that stay behind it.
- [security/usbguard/README.md](security/usbguard/README.md)
  - USBGuard USB device access control with rules stored encrypted via sops.

## SOPS

- [sops/README.md](sops/README.md)
  - sops-nix policy, what ships in the repo, host key preparation and rotation, and editing encrypted files safely.
- [sops/adding-secrets.md](sops/adding-secrets.md)
  - Adding a secret: the YAML shape, explicit key declarations, and runtime consumers.
- [sops/ci-evaluation.md](sops/ci-evaluation.md)
  - Secretless CI evaluation through `path:`, and the local store-copy hazard of `path:` commands.
- [sops/troubleshooting.md](sops/troubleshooting.md)
  - sops-nix error messages with their cause and fix.

## Technical Writing

- [technical-writing/style-guide.md](technical-writing/style-guide.md)
  - Rules for every hand-written page: the value test, banned content, shape, prose, host pages, and the docs-style hook.
- [technical-writing/scope-and-audience.md](technical-writing/scope-and-audience.md)
  - Rules for matching a page to its content type and for single-sourcing facts across pages.
- [technical-writing/drafting.md](technical-writing/drafting.md)
  - Rules for headings, structure, paragraphs, lists, callouts, and images.
- [technical-writing/editing.md](technical-writing/editing.md)
  - Rules for editing passes and terminology consistency.
- [technical-writing/code-samples.md](technical-writing/code-samples.md)
  - Rules for sample trustworthiness, conciseness, and placeholder naming.

## Troubleshooting

- [troubleshooting/nix-store-maintenance.md](troubleshooting/nix-store-maintenance.md)
  - Runbook defining the default Nix store repair workflow for each opted-in host.

## Usage

- [usage/README.md](usage/README.md)
  - Index of user-facing documentation for specific modules and features.
- [usage/espanso-usage.md](usage/espanso-usage.md)
  - Espanso text expander usage including enabling, default triggers, service management, and troubleshooting.
- [usage/espanso-matches.md](usage/espanso-matches.md)
  - Custom espanso matches, form, shell, and clipboard variables, and regex triggers.
- [usage/espanso-configuration.md](usage/espanso-configuration.md)
  - App-specific espanso configs, X11 and Wayland support, and the package override.
- [usage/magnitude.md](usage/magnitude.md)
  - Running Claude Code and Codex on local models served by Magnitude on songbird.
- [usage/pentesting-devshell.md](usage/pentesting-devshell.md)
  - Pentesting tools devshell usage including desktop launchers and adding new tools.
- [usage/podman-untrusted.md](usage/podman-untrusted.md)
  - Running untrusted images under gVisor with no network through `podman --module untrusted`.
- [usage/rustdesk.md](usage/rustdesk.md)
  - Self-hosted RustDesk over Cloudflare Mesh: privacy model, logins, non-NixOS device setup, troubleshooting.

## Hosts

### songbird

- [hosts/songbird/songbird-hardware.md](hosts/songbird/songbird-hardware.md)
  - Parts, storage roles, device inventory, and operating constraints of the `songbird` workstation.
- [hosts/songbird/songbird-configuration.md](hosts/songbird/songbird-configuration.md)
  - Non-obvious operational deviations from the hosts-common baseline.
- [hosts/songbird/songbird-runbook.md](hosts/songbird/songbird-runbook.md)
  - Validation procedure for a `songbird` change.
- [hosts/songbird/songbird-runbook-reinstall.md](hosts/songbird/songbird-runbook-reinstall.md)
  - Reinstall, first switch, secrets, and `/data` key-slot procedures for `songbird`.
- [hosts/songbird/songbird-runbook-windows.md](hosts/songbird/songbird-runbook-windows.md)
  - Booting Windows once, installing Windows on disk W, and converting portal to BitLocker.
- [hosts/songbird/songbird-runbook-vms.md](hosts/songbird/songbird-runbook-vms.md)
  - Running an ad-hoc virt-manager guest on the `default` network from a staged ISO.
- [hosts/songbird/songbird-troubleshooting.md](hosts/songbird/songbird-troubleshooting.md)
  - Known failures on `songbird` by symptom, each with its cause, diagnostic, and fix.
- [hosts/songbird/songbird-troubleshooting-windows.md](hosts/songbird/songbird-troubleshooting-windows.md)
  - Windows dual-boot and `/portal` failures on `songbird` by symptom, each with its cause, diagnostic, and fix.

## Agents

### Claude Code

- [agents/claude-code/skill-providers.md](agents/claude-code/skill-providers.md)
  - Declarative ownership and default availability for Claude Code skill providers.
- [agents/claude-code/skills.md](agents/claude-code/skills.md)
  - Technical manual for SKILL.md files covering frontmatter fields, invocation methods, execution lifecycle, and best practices.
- [agents/claude-code/writing-CLAUDE.md](agents/claude-code/writing-CLAUDE.md)
  - How to write CLAUDE.md files: persistent, always-active agent instructions loaded at session start.
- [agents/claude-code/scratchpad.md](agents/claude-code/scratchpad.md)
  - scratchpad

### Codex

- [agents/codex/configuration.md](agents/codex/configuration.md)
  - Configure Nix settings, feature flags, launch environment, and project trust; diagnose rejected configuration fields.

### MCP

- [agents/mcp/logseq.md](agents/mcp/logseq.md)
  - Logseq MCP server documentation for AI assistant integration with knowledge graphs (DB graphs only).

## Hardware

### Keyboards

- [hardware/keyboards/fc660c/README.md](hardware/keyboards/fc660c/README.md)
  - Leopold FC660C with the Hasu (TMK) Alt Controller: quick identification facts, the NixOS switch, and links to the rest of the set.
- [hardware/keyboards/fc660c/identification.md](hardware/keyboards/fc660c/identification.md)
  - Reproducible USB commands to confirm the Hasu Alt Controller and tell Vial firmware apart from stock TMK or plain QMK/VIA.
- [hardware/keyboards/fc660c/identification-hid.md](hardware/keyboards/fc660c/identification-hid.md)
  - The three HID interfaces, resolving a hidraw node, and decoding the raw HID report descriptor.
- [hardware/keyboards/fc660c/configuration.md](hardware/keyboards/fc660c/configuration.md)
  - The NixOS module, its board-scoped udev rule, the rule file's sort window, and bootloader access.
- [hardware/keyboards/fc660c/configuration-vial.md](hardware/keyboards/fc660c/configuration-vial.md)
  - Day-to-day remapping through Vial, the Esc+Enter unlock combo, and the actuation-point constraint.
- [hardware/keyboards/fc660c/flashing.md](hardware/keyboards/fc660c/flashing.md)
  - Entering the DFU bootloader, flashing with vial-qmk or dfu-programmer, and recovering from a bad flash.
- [hardware/keyboards/fc660c/firmware/README.md](hardware/keyboards/fc660c/firmware/README.md)
  - Building FC660C firmware on NixOS, the local keymap overlay for NKRO and actuation point, the flash script, and the ATmega32U4 flash budget.

## Apps

### Cloudflare

- [apps/cloudflare/README.md](apps/cloudflare/README.md)
  - Index for Cloudflare developer platform docs and local NixOS samples.
- [apps/cloudflare/acme-cloudflare-sample.md](apps/cloudflare/acme-cloudflare-sample.md)
  - Sample NixOS configuration for ACME certificate management using Cloudflare DNS-01 challenge.
- [apps/cloudflare/cloudflared-tunnel-sample.md](apps/cloudflare/cloudflared-tunnel-sample.md)
  - Sample NixOS configuration for Cloudflare Tunnel (cloudflared) with ingress rules and credential setup.
- [apps/cloudflare/containers/README.md](apps/cloudflare/containers/README.md)
  - Technical documentation index for Cloudflare Containers.
- [apps/cloudflare/containers/architecture.md](apps/cloudflare/containers/architecture.md)
  - Architecture, request flow, and rollout model for Cloudflare Containers.
- [apps/cloudflare/containers/configuration.md](apps/cloudflare/containers/configuration.md)
  - Wrangler, Dockerfile, environment, and deployment configuration for Cloudflare Containers.
- [apps/cloudflare/containers/api-reference.md](apps/cloudflare/containers/api-reference.md)
  - Container package properties, helper functions, methods, and TypeScript interfaces.
- [apps/cloudflare/containers/lifecycle.md](apps/cloudflare/containers/lifecycle.md)
  - Cold starts, warm requests, sleep behavior, shutdown, storage lifetime, and rollouts.
- [apps/cloudflare/containers/storage-networking.md](apps/cloudflare/containers/storage-networking.md)
  - Disk, R2 mount, ingress, egress, DNS, and network-isolation notes for Containers.
- [apps/cloudflare/containers/use-cases.md](apps/cloudflare/containers/use-cases.md)
  - Practical Cloudflare Containers examples and application patterns.
- [apps/cloudflare/containers/limitations-roadmap.md](apps/cloudflare/containers/limitations-roadmap.md)
  - Beta limitations, platform gaps, and roadmap notes for Cloudflare Containers.
- [apps/cloudflare/warp/README.md](apps/cloudflare/warp/README.md)
  - Cloudflare WARP on the fleet: service-token enrollment, per-host mode, Mesh reachability, coexistence.
- [apps/cloudflare/warp/deployment.md](apps/cloudflare/warp/deployment.md)
  - Runbook: Cloudflare objects, the sops payload, host enrollment, recording the Mesh address, token rotation.
- [apps/cloudflare/warp/troubleshooting.md](apps/cloudflare/warp/troubleshooting.md)
  - WARP symptoms with cause, diagnostic, and fix.

### Duplicati

- [apps/duplicati/README.md](apps/duplicati/README.md)
  - Maintainer reference for the duplicati-r2 service: architecture, options, runbooks, recovery, security.
- [apps/duplicati/operations.md](apps/duplicati/operations.md)
  - Runbooks for everyday duplicati-r2 changes: provisioning secrets, editing the manifest, manual backup and restore, post-deploy validation.
- [apps/duplicati/recovery.md](apps/duplicati/recovery.md)
  - Failure modes, repair flow, and the impact-analysis playbook for missing or damaged remote volumes.
- [apps/duplicati/reference.md](apps/duplicati/reference.md)
  - Complete option surface, manifest schema, and runtime artifact catalog for `services.duplicati-r2`.
- [apps/duplicati/security.md](apps/duplicati/security.md)
  - Threat model, secret layout, state-directory access controls, credential rotation, and bucket lifecycle posture.

### libvirt

- [apps/libvirt/README.md](apps/libvirt/README.md)
  - libvirt access, declared libvirt networks and how the reconciler applies them, staged media, removal, and failures.
- [apps/libvirt/guests.md](apps/libvirt/guests.md)
  - Declared guests: trust classes, how the reconciler defines them, disks and NVRAM, growth, removal, orphans, and failures.

### mpv

- [apps/mpv/README.md](apps/mpv/README.md)
  - Index for the mpv documentation set covering module composition, configuration, scripts, integrations, customization, and troubleshooting.
- [apps/mpv/1-architecture.md](apps/mpv/1-architecture.md)
  - Module layering, aggregator namespaces, host gating, and the NixOS-to-Home-Manager activation contract.
- [apps/mpv/2-configuration.md](apps/mpv/2-configuration.md)
  - Reference for every key the Home Manager mpv module writes to `mpv.conf` with rationale for non-default values.
- [apps/mpv/3-scripts-and-bindings.md](apps/mpv/3-scripts-and-bindings.md)
  - Script loading model through `extraScripts` and the rewrapped package, bundled scripts, and the keybinding conventions.
- [apps/mpv/3-lua-hooks.md](apps/mpv/3-lua-hooks.md)
  - The repo-local `playlist_filter.lua` and `ytdlp_cookies.lua` scripts, their modes, and browser resolution.
- [apps/mpv/4-integrations.md](apps/mpv/4-integrations.md)
  - XDG MIME defaults, MPRIS via playerctl, the `open-in-mpv` browser bridge, and the `video-cache` helper.
- [apps/mpv/5-customizing.md](apps/mpv/5-customizing.md)
  - Choosing the layer, overriding configuration keys, replacing the package, adjacent tools, personal overrides, and opting out per host.
- [apps/mpv/5-customizing-scripts.md](apps/mpv/5-customizing-scripts.md)
  - Adding packaged scripts through `extraScripts`, raw Lua files, and keybindings on one host.
- [apps/mpv/6-troubleshooting.md](apps/mpv/6-troubleshooting.md)
  - MIME default-assertion failures, codec gaps, and silent hwdec fallback.

### PDF Tooling

- [apps/pdf/toolkit.md](apps/pdf/toolkit.md)
  - Catalog of PDF-focused applications managed by this configuration covering viewers, structural inspectors, content extractors, and OCR engines.
- [apps/pdf/additional-tools-reference.md](apps/pdf/additional-tools-reference.md)
  - Reference catalog of PDF tools that complement the active toolkit, invocable ad hoc via `nix run`, `nix shell`, or `uvx`.

### R2 Cloud

- [apps/r2-cloud/README.md](apps/r2-cloud/README.md)
  - Index for `nix-R2-CloudFlare-Flake` consumer integration docs in this repo.
- [apps/r2-cloud/input-and-module-wiring.md](apps/r2-cloud/input-and-module-wiring.md)
  - How `inputs.r2-flake` is wired into registered NixOS and Home Manager hosts.
- [apps/r2-cloud/secrets-and-rendered-files.md](apps/r2-cloud/secrets-and-rendered-files.md)
  - Mapping from `secrets/r2.yaml` to `/run/secrets/r2/*` and HM env templates.
- [apps/r2-cloud/songbird-runtime.md](apps/r2-cloud/songbird-runtime.md)
  - Runtime contract for sync/restic/git-annex/r2 wrapper on this host.
- [apps/r2-cloud/home-manager-r2-cloud.md](apps/r2-cloud/home-manager-r2-cloud.md)
  - HM-side `programs.r2-cloud` load path and credential-source behavior.
- [apps/r2-cloud/validation-and-drift-checks.md](apps/r2-cloud/validation-and-drift-checks.md)
  - Operator checks to prove integration is still intact.
- [apps/r2-cloud/troubleshooting.md](apps/r2-cloud/troubleshooting.md)
  - Integration-specific failure diagnosis and repair paths.

### RDP

- [apps/rdp/README.md](apps/rdp/README.md)
  - Index for Remote Desktop (RDP) operator docs covering One Identity Safeguard RemoteApp access.
- [apps/rdp/safeguard-remoteapp-file-export.md](apps/rdp/safeguard-remoteapp-file-export.md)
  - Why file export/download fails inside a Safeguard RemoteApp session and the Safeguard channel-policy changes to request from the administrator.
