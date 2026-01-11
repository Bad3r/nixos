# Android Emulator Network Interception Plan

> **Status: DRAFT** — This plan was created 2025-10-28 but has not been implemented. The "Next Actions" section lists outstanding work required to operationalize this workflow.

## Objectives

- Stand up a reproducible Android Studio emulator stack on NixOS (X11 desktop) for authorized penetration testing.
- Guarantee traffic visibility and manipulation by integrating proxies, packet capture, and CA management from the outset.
- Keep tooling current without ad-hoc downloads by tracking SDK updates declaratively.

## Scope & Assumptions

- Target host: single System76 workstation running NixOS 25.05 or later with X11 session; virtualization extensions (VT-x/AMD-V) available in firmware.
- Workflows are executed inside the repository’s flakes/dev shells; no legacy `android` tool usage.
- Physical devices are out-of-scope for this phase; focus is Android Virtual Devices (AVDs).

## Phase 0 – Host Readiness

- Verify KVM acceleration and permissions before touching SDKs: `nix develop` ⇢ `emulator -accel-check`, `lsmod | grep kvm`, and `groups` (expect `kvm`, `adbusers`).
- Keep X11 stable by defaulting the emulator to software rendering: add `-gpu swiftshader_indirect` to launch aliases to bypass brittle OpenGL stacks while retaining Quick Boot compatibility.
- Open firewall paths for localhost interception. Emulator traffic that points to 10.0.2.2 hits the host loopback; ensure proxy ports (for example 8080/8443) are allowed.

## Phase 1 – Nix Flake Integration

- Pin the Android SDK and emulator via `android-nixpkgs`, which republishes Google’s repositories daily so tool revisions stay fresh without manual downloads.
- Nixpkgs’ androidenv now auto-tracks upstream releases; pipe these packages through flakes rather than copying ZIPs into `$HOME`.
- Suggested flake excerpt:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    android-nixpkgs.url = "github:tadfisher/android-nixpkgs";
  };

  outputs = { self, nixpkgs, android-nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
        cmdline-tools-latest
        emulator
        platform-tools
        "platforms;android-35"
        "system-images;android-35;google_apis;x86_64"
      ]);
    in {
      devShells.${system}.android = pkgs.mkShell {
        buildInputs = [
          androidSdk
          pkgs.jdk17
          pkgs.mitmproxy
        ];
        ANDROID_HOME = "${androidSdk}";
        ANDROID_SDK_ROOT = "${androidSdk}";
        ANDROID_USER_HOME = "$HOME/.android";
      };
    };
}
```

- Add host module glue (excerpt): `programs.adb.enable = true;`, ensure `users.users.vx.extraGroups = [ "adbusers" "kvm" "wireshark" ];` so ADB, emulator, and packet capture can run without sudo.

## Phase 2 – SDK & AVD Provisioning

- Enter the dev shell: `nix develop .#android --command $SHELL`.
- Accept licenses and hydrate packages once per host:
  - `sdkmanager --sdk_root="$ANDROID_HOME" --licenses`
  - `sdkmanager --sdk_root="$ANDROID_HOME" "cmdline-tools;latest" "platforms;android-35" "system-images;android-35;google_apis;x86_64" "platform-tools"`
- Define base devices with `avdmanager create avd -n Pixel8Pentest -k "system-images;android-35;google_apis;x86_64" --device pixel_8`.
- Document all AVDs (`emulator -list-avds`) under `docs/pentest-avds.md` so the team shares identical targets.

## Phase 3 – Launch & Interception Pipeline

- Standard launch wrapper (store under `scripts/pentest-emulator.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail
AVD_NAME=${1:-Pixel8Pentest}
CAPTURE_DIR=${CAPTURE_DIR:-$HOME/captures}
mkdir -p "$CAPTURE_DIR"
STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
exec emulator @"$AVD_NAME" \
  -http-proxy 127.0.0.1:8080 \
  -tcpdump "$CAPTURE_DIR/${AVD_NAME}_${STAMP}.pcap" \
  -writable-system \
  -gpu swiftshader_indirect \
  -accel on \
  -no-snapshot-save
```

- `-http-proxy` forces every TCP request through the host proxy.
- `-tcpdump` produces libpcap captures for Wireshark or Zeek review.

- Run mitmproxy alongside the emulator to intercept and modify requests, taking advantage of its full HTTP/3 and QUIC handling for 2025-era apps: `mitmproxy --mode wireguard --listen-port 8080`.
- For apps that ship certificate pinning, plan on:
  1. `adb root && adb remount` (AOSP images only) to mount `/system` read/write.
  2. Push the team CA into `/system/etc/security/cacerts/` and run `update-ca-certificates`.
  3. Leverage Frida/Magisk tools from the pentesting dev shell for dynamic bypasses (documented separately).
- Maintain clean routing: emulator sees host loopback as 10.0.2.2—proxy tooling must listen on 127.0.0.1.

## Phase 4 – Validation & Observability

- Launch checklist per assessment:
  - `emulator -accel-check` returns `KVM ... usable`.
  - mitmproxy shows negotiated HTTP/3/QUIC flows; archive HAR and flow exports with case notes.
  - Confirm `tcpdump` output opens in Wireshark and contains decrypted payloads when mitmproxy keys are exported.
- For multi-run capture campaigns, consider the PARROT framework to orchestrate AVD boot ⇒ app script ⇒ proxy capture ⇒ labelled artifact storage.

## Maintenance & Update Strategy

- Schedule a weekly `nix flake update` to pull new SDK builds from android-nixpkgs; reviewers can diff emulator, system images, and platform-tools updates before merging.
- androidenv automation in nixpkgs-unstable already runs the upstream test suite—track failure reports in Hydra before bumping production hosts.
- Pin mitmproxy major versions in the dev shell; monitor release notes for protocol regressions affecting QUIC interception.

## Risk Log & Mitigations

- **GPU instability under proprietary drivers**: always start with `swiftshader_indirect`; escalate only if hardware acceleration is required for test fidelity.
- **Proxy bypass by UDP/QUIC traffic**: enforce mitmproxy WireGuard mode or network rules to redirect UDP 443, and audit flows captured in PARROT datasets.
- **Certificate pinning blocks**: budget time to deploy Frida scripts or Magisk modules per target app; pre-stage templates in `tools/frida/`.
- **SDK drift**: use PR templates to record `sdkmanager --list` output and the validation commands (`nix fmt`, `nix flake check`, `emulator -accel-check`) in commit messages, matching repo policy.

## Next Actions

1. Land flake modifications + dev shell on a feature branch; run `nix flake check`.
2. Generate `scripts/pentest-emulator.sh` and store captured traffic under `~/captures` with retention rules.
3. Pilot run: launch emulator, install mitmproxy CA, intercept a known test app, confirm decrypted HTTP/3 flow, and archive artifacts in the engagement notebook.
4. Fold the workflow into `docs/pentesting-devshell.md` once validated, noting dependencies on this plan.
