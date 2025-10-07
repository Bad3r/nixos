# USBGuard Implementation Plan

## Phase 1 — Assessment & Scope Definition

### Task 1.1 — Enumerate USB Attack Surface

- [ ] Collect current USB device inventories per host (use `lsusb`, `usbguard list-devices` on gold images).
- [ ] Group devices by function (human interface, storage, hubs, vendor-specific) to inform policy categories.
- [ ] Flag high-risk classes (mass storage, HID emulation) for stricter handling in later phases.

### Task 1.2 — Classify Host Profiles

- [ ] Segment fleet into baseline hosts and special-case hardware (e.g., System76 laptops, lab controllers).
- [ ] Document host-specific peripherals that must remain functional (embedded dev boards, Thunderbolt docks).
- [ ] Record ownership/stewards for each host class to sign off on policy changes.

## Phase 2 — Policy Authoring & Allow-List Ownership

### Task 2.1 — Draft Global Default Rules

- [x] On a hardened reference host, run `sudo usbguard generate-policy --no-hash` and capture output.
- [x] Review output, removing transient or disallowed devices; categorize rules by interface class.
- [x] Normalize rule order and comments, then store the curated baseline in a dedicated module attribute (e.g., `modules/apps/usbguard/base-rules.nix`) exposed as `usbguardBaseRules`.
- [x] Set `services.usbguard.rules = lib.mkDefault usbguardBaseRules;` so Nix owns the allow-list while keeping overrides possible.citenixpkgs/nixos/modules/services/security/usbguard.nix:55

### Task 2.2 — Author Host-Specific Overlays

- [x] For each special-case class (e.g., System76), define a `usbguardHostRules` string containing only the additional `allow` statements.
- [x] In the host module, set `services.usbguard.rules = lib.concatStringsSep "\n" [ usbguardBaseRules usbguardHostRules ];` (or use `lib.mkMerge` with a host-specific override) so the baseline is reused verbatim and only host additions change.
- [x] Gate these overlays behind host predicates (e.g., `mkIf (config.networking.hostName == "system76-<model>")`).
- [x] Capture rationale and device IDs for each host-specific rule inside module comments.

### Task 2.3 — Define Secret-Backed Rule Files (Optional Devices)

- [x] When rules include sensitive identifiers, create a `sops.secrets.usbguard-rules` entry targeting `/run/secrets/usbguard.rules` with `owner = "root"; group = "root"; mode = "0400"; neededForUsers = true;`.
- [x] On hosts using the secret file, set `services.usbguard.rules = lib.mkForce null;` and `services.usbguard.ruleFile = "/run/secrets/usbguard.rules";` so the daemon reads the managed secret instead of the inline rules.citenixpkgs/nixos/modules/services/security/usbguard.nix:22nixpkgs/nixos/modules/services/security/usbguard.nix:55
- [ ] Add CI checks ensuring the secret manifest exists before evaluation (e.g., `nix flake check` with dummy fixtures).
- [x] Document operational procedures for rotating the secret and reloading usbguard without service interruption.

## Phase 3 — NixOS Integration & IPC Governance

### Task 3.1 — Enable and Harden USBGuard Service

- [x] Set `services.usbguard.enable = true;` globally and ensure the package remains in closure via `environment.systemPackages`.citenixpkgs/nixos/modules/services/security/usbguard.nix:49nixpkgs/nixos/modules/services/security/usbguard.nix:188
- [x] Confirm the generated daemon config tracks our rules, policies, and IPC allow lists.
- [x] Document policy defaults (`implicitPolicyTarget = "block"`, etc.) and adjust only as justified.citenixpkgs/nixos/modules/services/security/usbguard.nix:89nixpkgs/nixos/modules/services/security/usbguard.nix:103nixpkgs/nixos/modules/services/security/usbguard.nix:123

### Task 3.2 — Manage IPC/D-Bus Access

- [x] Configure `services.usbguard.IPCAllowedUsers` and `.IPCAllowedGroups` to include only incident response staff and automation accounts.citenixpkgs/nixos/modules/services/security/usbguard.nix:148nixpkgs/nixos/modules/services/security/usbguard.nix:160
- [x] Enable D-Bus support (`services.usbguard.dbus.enable = true;`) where interactive tooling (e.g., usbguard-notifier) is required.citenixpkgs/nixos/modules/services/security/usbguard.nix:178nixpkgs/nixos/modules/services/security/usbguard.nix:236
- [x] Verify the module-provided Polkit rule grants requested groups the needed actions and nothing more.citenixpkgs/nixos/modules/services/security/usbguard.nix:236

### Task 3.3 — Leverage Strict Device Cgroup Controls

- [x] Leave the module’s `DevicePolicy = "strict"` and `DeviceAllow = "/dev/null rw"` in place to ensure unauthorized USB devices never enumerate fully.citenixpkgs/nixos/modules/services/security/usbguard.nix:210
- [x] Review additional hardening flags (e.g., `PrivateDevices`, `SystemCallFilter`) and extend if kernel supports further lockdowns.citenixpkgs/nixos/modules/services/security/usbguard.nix:208nixpkgs/nixos/modules/services/security/usbguard.nix:216

## Phase 4 — Monitoring & Incident Response Integration

### Task 4.1 — Audit Log Wiring

- [x] Introduce auditd via `security.auditd.enable = true;` (new service for this plan) and define rules to flag USB authorization denials.
- [x] Keep logs local; rely on `journalctl -u usbguard` and `ausearch -k usbguard-policy` during investigations.
- [x] Tag usbguard unit logs with structured metadata via `systemd.services.usbguard.serviceConfig.LogExtraFields` so local filtering stays expressive.
- [ ] Review journald rate-limiting to ensure bursts of USB events are retained.

### Task 4.2 — Notification & UX

- [x] Package `usbguard-notifier` on desktops needing user prompts and restrict execution to trusted sessions.
- [ ] Document using `usbguard list-devices`, `usbguard allow-device`, and revocation workflows.

## Phase 5 — Validation, Rollout & Maintenance

### Task 5.1 — Automated Testing

- [ ] Extend `nixos/tests/usbguard.nix` (or add custom tests) to cover default and host-specific rules.citenixpkgs/nixos/tests/usbguard.nix:21
- [ ] Run `nix flake check --accept-flake-config` and targeted `nix build .#nixosConfigurations.<host>` before merges.
- [ ] Simulate USB insertions in QEMU to confirm blocked devices remain “blocked” and allowed devices enumerate.

### Task 5.2 — Staged Rollout

- [ ] Deploy to canary hosts, monitor for false positives/negatives.
- [ ] Iterate on policy adjustments, merging fixes through PRs with documented validation commands.
- [ ] Roll out to remaining hosts in waves, pausing on any regression signals.

### Task 5.3 — Ongoing Governance

- [ ] Schedule quarterly reviews of device inventory and policy relevance.
- [ ] Track upstream usbguard releases; refresh package pin as needed.
- [ ] Maintain runbooks for emergency device authorization overrides (documented CLI/D-Bus steps).

## References

- `nixpkgs/nixos/modules/services/security/usbguard.nix:49`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:22`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:55`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:89`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:103`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:123`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:148`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:160`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:178`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:188`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:208`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:210`
- `nixpkgs/nixos/modules/services/security/usbguard.nix:236`
- `nixpkgs/nixos/tests/usbguard.nix:21`
