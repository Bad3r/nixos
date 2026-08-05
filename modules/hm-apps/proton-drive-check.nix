/*
  Check: proton-drive-sync builds, and a bisync safety abort latches the tuple
  (modules/hm-apps/proton-drive.nix).

  home.packages carries the script only when protondriveReady is true, which
  needs secrets/rclone_protondrive.env. No tracked host ships that file and CI
  has no secrets submodule at all, so writeShellApplication's shellcheck pass
  has never run on the script and none of its abort handling has ever executed.

  Builds a standalone Home Manager configuration the way
  modules/browsers/firefoxpwa/module-check.nix does, with osConfig stubbed to
  make the remote ready and secretsRoot pointed at an in-repo fixture, then
  replaces programs.rclone.package with a stub replaying a scripted exit code
  and stderr so the script's control flow, not rclone, is under test.

  Runs under the build sandbox's private /tmp because the state root and local
  path are pinned at eval time; the pre-existing-state guard below turns an
  unsandboxed build into a failure instead of a stale-state pass.
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
            printf '%s\n' "$*" >> "$RCLONE_STUB_CALLS"
            if [ -n "''${RCLONE_STUB_STDERR:-}" ]; then
              printf '%s\n' "$RCLONE_STUB_STDERR" >&2
            fi
            exit "''${RCLONE_STUB_EXIT:-0}"
          '';

          hm = inputs.home-manager.lib.homeManagerConfiguration {
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
                services.protonDriveSync.enable = true;
              }
            ];
            extraSpecialArgs = {
              osConfig = {
                programs.rclone.extended.enable = true;
                security.repoSecrets.enable = true;
                sops.secrets."rclone/protondrive-env".path = "${root}/protondrive-env";
              };
              secretsRoot = ./proton-drive-check-fixtures;
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

                state=${lib.escapeShellArg stateDir}
                local_path=${lib.escapeShellArg localPath}
                sync=${lib.getExe syncScript}

                if [ -e "$state" ]; then
                  echo "hm-apps/proton-drive-sync: $state already exists; this check needs the sandbox's private /tmp" >&2
                  exit 1
                fi

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

                touch "$out"
              '';
        in
        assert lib.assertMsg (
          syncScript != null
        ) "hm-apps/proton-drive-sync: the stubbed configuration must install proton-drive-sync";
        assert lib.assertMsg (lib.all (entry: entry.assertion)
          hm.config.assertions
        ) "hm-apps/proton-drive-sync: the stubbed configuration must satisfy its own assertions";
        builtins.deepSeq units drive;
    };
}
