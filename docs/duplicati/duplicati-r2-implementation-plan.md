# Duplicati R2 Module Implementation Checklist

- [x] **Module Scaffolding**
  - [x] Define `services.duplicati-r2` option namespace with core attributes (`enable`, `configFile`, `environmentFile`, `package`, `credentials`, `targets`, `verify`).
  - [x] Support encrypted manifests delivered via `configFile` while keeping an attrset interface for tests and inline prototypes.
  - [x] Keep defaults for `environmentFile` (`/etc/duplicati-r2.env`), `stateDir` (`/var/lib/duplicati-r2`), and retention (`14D:1D,12M:1M`) when the manifest omits them.
  - [x] Document option descriptions with examples referencing Duplicati CLI expectations for Cloudflare R2.

- [x] **Secrets & Environment File Wiring**
  - [x] Map `services.duplicati-r2.credentials` attrset into `sops.secrets` entries linking to `secrets/duplicati-r2.yaml` selectors.
  - [x] Emit `sops.templates."duplicati-r2-env"` whose `path = cfg.environmentFile`, with placeholders for each credential key and file permissions `0400`.
  - [x] Add assertion ensuring `cfg.environmentFile` is absolute.
  - [x] Export credential defaults to services via environment variables rather than static `EnvironmentFile=` declarations.

- [x] **Backup & Verify Script Derivations**
  - [x] Create `pkgs.writeShellApplication` for `duplicati-r2-backup` handling env vars, path validation, retention flags, and S3 endpoint derivation (`AWS_ENDPOINT_URL`, `s3-disable-chunk-encoding=true`, etc.).
  - [x] Implement matching verify script (`duplicati-r2-verify`) to run `duplicati-cli test` with optional sample count.
  - [x] Expose script paths via module scope so systemd services can reference them without re-evaluation.
  - [x] Ensure scripts fail fast when required credentials are missing.

- [x] **Runtime Systemd Unit Generation**
  - [x] Build a generator script that reads `/run/duplicati-r2/config.json` and emits backing services/timers under `/run/systemd/system`.
  - [x] Create per-target backup units exporting `DUPLICATI_R2_CONFIG`, `DUPLICATI_R2_TARGET`, and default paths for state/env files.
  - [x] Generate optional per-target `duplicati-r2-verify-<name>.service`/`.timer` when the manifest defines a `verify` block.
  - [x] Add `systemd.tmpfiles.rules` to create `stateDir` and ensure ownership/permissions.

- [ ] **NixOS Test Coverage**
  - [x] Add NixOS test (`tests/duplicati-r2.nix`) spinning up nodes to assert:
    - [x] Services and timers are instantiated for two distinct targets.
    - [x] `systemctl show duplicati-r2-backup-*.timer -p OnCalendar` matches configured values.
    - [x] Environment variables expose `DUPLICATI_R2_CONFIG` and packaged scripts are referenced in `ExecStart`.
  - [x] Include verify timer scenario and confirm it is conditionally absent when `cfg.verify = null`.
  - [x] Include verify timer scenario and confirm it is conditionally absent when `services.duplicati-r2.verify` is null.
  - [ ] Register the test under `flake.checks` and verify `nix flake check` passes.

- [ ] **Validation & Lint Hooks**
  - [x] Add development shell helper (`scripts/validate-oncalendar.sh`) that runs `systemd-analyze calendar` for all configured schedules; surface via module assertion with `pkgs.runCommand` during evaluation.
  - [x] Integrate new module into `nix fmt` by ensuring formatting passes for example configurations.

- [ ] **Documentation**
  - [x] Update `docs/duplicati-r2-backups.md` to reflect manifest-first configuration, encrypted via SOPS templates.
  - [x] Add troubleshooting section covering missing credentials, invalid `OnCalendar`, and Duplicati CLI exit codes.
  - [x] Provide migration guidance for writing SOPS secrets corresponding to the new `credentials` attrset.

- [ ] **CI & Flake Integration**
  - [ ] Register NixOS test in `flake.nix` (`checks` attribute).
  - [ ] Ensure `nix flake check --accept-flake-config` runs the new test locally.
  - [ ] Add release note entry summarizing the new service module.
