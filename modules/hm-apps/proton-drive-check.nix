/*
  Check: proton-drive-sync builds, and a bisync safety abort latches the tuple
  (modules/hm-apps/proton-drive.nix).

  home.packages carries the script only when protondriveReady is true. CI has no
  secrets submodule and no 1Password session, and no `nix flake check` step
  builds a host toplevel, so writeShellApplication's shellcheck pass had never
  run on the script and none of its abort handling had ever executed.

  Builds a standalone Home Manager configuration the way
  modules/browsers/firefoxpwa/module-check.nix does, with osConfig stubbed to
  make the remote ready and secretsRoot pointed at an in-repo fixture, then
  replaces programs.rclone.package with a stub replaying a scripted exit code
  and stderr so the script's control flow, not rclone, is under test.

  Both credential sources gate the same script, so the op:// source is asserted
  to install it without any secret present, while protonDrive.enable = false and
  rclone.extended.enable = false are each asserted to withhold it. That covers
  protondriveReady's three inputs (rclone, protonDrive, authSource) by eval
  alone.

  Runs under the build sandbox's private /tmp because the state root and local
  path are pinned at eval time; the check creates that whole root itself and
  fails when it already exists, so an unsandboxed build cannot pass on stale
  state or write through a planted symlink.
*/
{
  lib,
  inputs,
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."hm-apps/proton-drive-sync" =
        let
          root = "/tmp/proton-drive-sync-check";
          stateDir = "${root}/state/proton-drive-sync";
          localPath = "${root}/home/ProtonDrive";

          rcloneStub = pkgs.writeShellScriptBin "rclone" ''
            if [ -n "''${RCLONE_LOG_FILE:-}''${RCLONE_LOG_FORMAT:-}''${RCLONE_LOG_LEVEL:-}''${RCLONE_SYSLOG:-}''${RCLONE_USE_JSON_LOG:-}" ]; then
              echo "rclone stub: a log-routing RCLONE_ variable reached rclone" >&2
              exit 99
            fi
            printf '%s\n' "$*" >> "$RCLONE_STUB_CALLS"
            if [ -n "''${RCLONE_STUB_STDERR:-}" ]; then
              printf '%s\n' "$RCLONE_STUB_STDERR" >&2
            fi
            exit "''${RCLONE_STUB_EXIT:-0}"
          '';

          opRef = field: "op://check/protondrive/${field}";

          mkHm =
            {
              protonDrive,
              secretsRoot ? ./proton-drive-check-fixtures,
              extraArgs ? [ ],
              rcloneEnabled ? true,
              serviceEnable ? protonDrive.enable,
            }:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                config.flake.homeManagerModules.apps.proton-drive
                {
                  home = {
                    username = "hm-smoke";
                    homeDirectory = "${root}/home";
                    stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
                    enableNixpkgsReleaseCheck = false;
                  };
                  programs.home-manager.enable = true;
                  programs.rclone.package = rcloneStub;
                  xdg.stateHome = "${root}/state";
                  xdg.configHome = "${root}/config";
                  services.protonDriveSync = {
                    enable = serviceEnable;
                    inherit extraArgs;
                  };
                }
              ];
              extraSpecialArgs = {
                osConfig = {
                  programs.rclone.extended = {
                    enable = rcloneEnabled;
                    inherit protonDrive;
                  };
                  security.repoSecrets.enable = true;
                  sops.secrets."rclone/protondrive-env".path = "${root}/protondrive-env";
                };
                inherit secretsRoot;
              };
            };

          installsScript =
            hmConfig: lib.any (drv: (drv.name or "") == "proton-drive-sync") hmConfig.config.home.packages;

          hm = mkHm {
            protonDrive = {
              enable = true;
              authSource = "sops";
            };
          };

          # The op:// source authenticates through the activation script at run
          # time, so no secret exists at eval and secretsRoot must not matter.
          onePasswordHm = mkHm {
            secretsRoot = "${./proton-drive-check-fixtures}/missing";
            protonDrive = {
              enable = true;
              authSource = "onePassword";
              onePassword = {
                usernameRef = opRef "username";
                passwordRef = opRef "password";
                otpRef = opRef "one-time password";
                mailboxPasswordRef = opRef "mailbox";
              };
            };
          };

          # otp_secret_key and mailbox_password are per-account optional (2FA
          # / two-password accounts only); an empty ref must still be ready.
          onePasswordNoOtpHm = mkHm {
            secretsRoot = "${./proton-drive-check-fixtures}/missing";
            protonDrive = {
              enable = true;
              authSource = "onePassword";
              onePassword = {
                usernameRef = opRef "username";
                passwordRef = opRef "password";
                otpRef = "";
                mailboxPasswordRef = "";
              };
            };
          };

          disabledHm = mkHm {
            protonDrive = {
              enable = false;
              authSource = "sops";
            };
          };

          # The system-side rclone module renders the [protondrive] remote this
          # script syncs against, so a ready credential source is not enough.
          # The timer stays off here because its own assertion would fire first.
          rcloneDisabledHm = mkHm {
            rcloneEnabled = false;
            serviceEnable = false;
            protonDrive = {
              enable = true;
              authSource = "sops";
            };
          };

          # Routing rclone's log away from stderr would leave the abort below
          # unlatched, so the module must refuse the argument at eval.
          logRoutedHm = mkHm {
            extraArgs = [ "--log-file=/tmp/rclone.log" ];
            protonDrive = {
              enable = true;
              authSource = "sops";
            };
          };

          syncScript = lib.findFirst (
            drv: (drv.name or "") == "proton-drive-sync"
          ) null hm.config.home.packages;

          # The units are declared but never installed here, so force the
          # attributes a real switch would render.
          units = {
            execStart = hm.config.systemd.user.services.proton-drive-sync.Service.ExecStart;
            timer = hm.config.systemd.user.timers.proton-drive-sync.Timer;
          };

          drive =
            pkgs.runCommand "proton-drive-sync-check"
              {
                passthru.runtimeCheck = true;
                nativeBuildInputs = [
                  pkgs.coreutils
                  pkgs.findutils
                  pkgs.gnugrep
                ];
              }
              ''
                set -o errexit -o nounset -o pipefail

                check_root=${lib.escapeShellArg root}
                state=${lib.escapeShellArg stateDir}
                local_path=${lib.escapeShellArg localPath}
                sync=${lib.getExe syncScript}

                # Every path below is a fixed /tmp path, so without the sandbox's
                # private /tmp another user could plant the root and have the
                # mkdir and seed-file writes below follow its symlinks. mkdir
                # fails on an existing directory or symlink, which also catches
                # leftover state from an earlier unsandboxed run.
                if ! mkdir -m 700 -- "$check_root" 2>/dev/null; then
                  echo "hm-apps/proton-drive-sync: $check_root already exists; this check needs the sandbox's private /tmp" >&2
                  exit 1
                fi
                trap 'rm -rf -- "$check_root"' EXIT

                export HOME=${lib.escapeShellArg "${root}/home"}
                mkdir -p "$local_path"
                : > "$local_path/seed"
                RCLONE_STUB_CALLS="$TMPDIR/rclone-calls"
                export RCLONE_STUB_CALLS
                : > "$RCLONE_STUB_CALLS"

                fail() {
                  echo "hm-apps/proton-drive-sync: $1" >&2
                  exit 1
                }
                marker_count() { find "$state" -maxdepth 1 -name "$1" | wc -l; }
                call_count() { wc -l < "$RCLONE_STUB_CALLS"; }

                RCLONE_STUB_EXIT=0 "$sync" --resync
                [ "$(marker_count 'initialized-*')" -eq 1 ] || fail "--resync must write the baseline marker"
                [ "$(marker_count 'aborted-*')" -eq 0 ] || fail "--resync must not latch"

                # rclone's bisync safety checks set abort without critical, so
                # they leave the listings valid and exit non-zero having changed
                # nothing. Without the latch the timer recomputes this abort from
                # a full listing of both sides every interval, forever.
                rc=0
                RCLONE_STUB_EXIT=2 \
                RCLONE_LOG_FILE=/dev/null RCLONE_SYSLOG=true RCLONE_USE_JSON_LOG=true \
                RCLONE_LOG_LEVEL=NOTICE RCLONE_LOG_FORMAT=nolevel \
                RCLONE_STUB_STDERR='ERROR : Safety abort: too many deletes (>25%, 8 of 8) on Path1 "/x". Run with --force if desired.' \
                  "$sync" || rc=$?
                [ "$rc" -ne 0 ] || fail "a bisync safety abort must fail the run"
                [ "$(marker_count 'aborted-*')" -eq 1 ] || fail "a bisync safety abort must latch the tuple"
                [ "$(marker_count 'initialized-*')" -eq 1 ] || fail "a bisync safety abort must keep the baseline marker"

                before=$(call_count)
                rc=0
                RCLONE_STUB_EXIT=0 "$sync" || rc=$?
                [ "$rc" -eq 1 ] || fail "a latched tuple must exit 1"
                [ "$(call_count)" -eq "$before" ] || fail "a latched tuple must not reach rclone"

                RCLONE_STUB_EXIT=0 "$sync" --force
                [ "$(marker_count 'aborted-*')" -eq 0 ] || fail "--force must release the latch"
                grep -q -- '--force' "$RCLONE_STUB_CALLS" || fail "--force must reach rclone"

                # A transient backend failure must keep retrying on the timer;
                # latching it would strand the sync until a human runs --force.
                rc=0
                RCLONE_STUB_EXIT=5 \
                RCLONE_STUB_STDERR='ERROR : Attempt 1/3 failed: connection reset by peer' \
                  "$sync" || rc=$?
                [ "$rc" -ne 0 ] || fail "a transient rclone failure must fail the run"
                [ "$(marker_count 'aborted-*')" -eq 0 ] || fail "a transient rclone failure must not latch"

                # An INFO line echoes the transferred path, so the abort text can
                # reach the log without either safety check having fired.
                rc=0
                RCLONE_STUB_EXIT=5 \
                RCLONE_STUB_STDERR='2026/01/01 00:00:00 INFO  : notes/Safety abort: too many deletes.md: Copied (new)' \
                  "$sync" || rc=$?
                [ "$rc" -ne 0 ] || fail "the stubbed failure must fail the run"
                [ "$(marker_count 'aborted-*')" -eq 0 ] || fail "a transferred path naming the abort must not latch"

                # The second safety check rclone releases with --force.
                rc=0
                RCLONE_STUB_EXIT=2 \
                RCLONE_STUB_STDERR='2026/01/01 00:00:00 ERROR : Safety abort: all files were changed on Path1 "/x". Run with --force if desired.' \
                  "$sync" || rc=$?
                [ "$rc" -ne 0 ] || fail "an all-files-changed abort must fail the run"
                [ "$(marker_count 'aborted-*')" -eq 1 ] || fail "an all-files-changed abort must latch the tuple"

                # The other release the refusal message advertises, on a
                # different branch than --force.
                RCLONE_STUB_EXIT=0 "$sync" --resync
                [ "$(marker_count 'aborted-*')" -eq 0 ] || fail "--resync must release the latch"
                [ "$(marker_count 'initialized-*')" -eq 1 ] || fail "--resync must keep the baseline marker"

                touch "$out"
              '';
        in
        assert lib.assertMsg (
          syncScript != null
        ) "hm-apps/proton-drive-sync: the sops source must install proton-drive-sync";
        assert lib.assertMsg (installsScript onePasswordHm)
          "hm-apps/proton-drive-sync: op:// references must install proton-drive-sync with no secret present";
        assert lib.assertMsg (installsScript onePasswordNoOtpHm)
          "hm-apps/proton-drive-sync: an empty otpRef/mailboxPasswordRef must still be ready (per-account optional fields)";
        assert lib.assertMsg (
          !installsScript disabledHm
        ) "hm-apps/proton-drive-sync: protonDrive.enable = false must withhold proton-drive-sync";
        assert lib.assertMsg (!installsScript rcloneDisabledHm)
          "hm-apps/proton-drive-sync: programs.rclone.extended.enable = false must withhold proton-drive-sync";
        assert lib.assertMsg (lib.all (entry: entry.assertion)
          hm.config.assertions
        ) "hm-apps/proton-drive-sync: the stubbed configuration must satisfy its own assertions";
        # home-manager throws on the whole configuration when an assertion
        # fails, so a rejected extraArg reads as an eval failure here.
        assert lib.assertMsg (
          !(builtins.tryEval logRoutedHm.config.home.packages).success
        ) "hm-apps/proton-drive-sync: --log-file in extraArgs must fail an assertion";
        builtins.deepSeq units drive;
    };
}
