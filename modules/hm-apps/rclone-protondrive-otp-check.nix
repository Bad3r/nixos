/*
  Check: the 1Password OTP reference resolves to a TOTP seed, or fails loudly
  (modules/hm-apps/rclone.nix, activation entry configureRcloneConfig).

  That parsing decides between three outcomes on every activation of every
  shareCommon host, because modules/hosts/common/rclone-protondrive-1password.nix
  ships otpRef for all of them: render otp_secret_key, exit 1 and abort the whole
  Home Manager activation, or render a [protondrive] stanza with no otp_secret_key
  at all. Only the third is silent, and it is the one that produces a remote which
  cannot authenticate. Nothing executed the branch before this check: the sibling
  proton-drive-sync check covers the sync script, not the activation script.

  The activation text is parameterized entirely through shell variables assigned
  at its top, so it runs here unmodified. security.wrapperDir selects the op
  binary and programs.rclone.package selects the rclone binary, so pointing both
  at stubs puts the parsing under test rather than 1Password or rclone. The op
  stub replays a scripted field value, and the rclone obscure stub is
  deterministic where the real one draws a random IV per call.

  The activation entry is a raw DAG string, so unlike the sync script it never
  passes through writeShellApplication's shellcheck; the check lints it here.

  Runs under the build sandbox's private /tmp because xdg.configHome is pinned at
  eval time; the check creates that whole root itself and fails when it already
  exists, so an unsandboxed build cannot pass on stale state or write through a
  planted symlink.
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
      checks."hm-apps/rclone-protondrive-otp" =
        let
          root = "/tmp/rclone-protondrive-otp-check";

          opStub = pkgs.writeShellScriptBin "op" ''
            if [ "''${1:-}" != read ]; then
              echo "op stub: expected 'read', got: $*" >&2
              exit 1
            fi
            # A locked desktop app, and equally the exit 124 of the timeout the
            # script wraps each read in.
            if [ -n "''${OP_STUB_FAIL-}" ]; then
              echo "op stub: vault is locked" >&2
              exit 1
            fi
            ref="''${3:-}"
            case "''${ref##*/}" in
              username) printf '%s' "''${OP_STUB_USERNAME-user@proton.me}" ;;
              password) printf '%s' "''${OP_STUB_PASSWORD-proton-password}" ;;
              "one-time password") printf '%s' "''${OP_STUB_OTP-}" ;;
              mailbox) printf '%s' "''${OP_STUB_MAILBOX-}" ;;
              *)
                echo "op stub: unknown reference: $ref" >&2
                exit 1
                ;;
            esac
          '';

          # The real obscure draws a fresh random IV per call, so its output
          # cannot be asserted on; this one is reversible by inspection.
          rcloneStub = pkgs.writeShellScriptBin "rclone" ''
            if [ "''${1:-}" != obscure ]; then
              echo "rclone stub: expected 'obscure', got: $*" >&2
              exit 1
            fi
            printf 'obscured:%s' "$(cat)"
          '';

          mkHm =
            { mailboxPasswordRef }:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                # The module declares a sops template for the r2 endpoint
                # unconditionally, so its options must exist even though
                # home.r2Secrets.enable is off here.
                inputs.sops-nix.homeManagerModules.sops
                config.flake.homeManagerModules.apps.rclone
                {
                  home = {
                    username = "hm-smoke";
                    homeDirectory = "${root}/home";
                    stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
                    enableNixpkgsReleaseCheck = false;
                  };
                  programs.home-manager.enable = true;
                  programs.rclone.package = rcloneStub;
                  xdg.configHome = "${root}/config";
                }
              ];
              extraSpecialArgs = {
                # No secret exists at eval under the op:// source, and a present
                # one would additionally arm the gdrive and sops branches.
                secretsRoot = "${./proton-drive-check-fixtures}/missing";
                osConfig = {
                  security.repoSecrets.enable = true;
                  # Selects "${security.wrapperDir}/op" as the op executable,
                  # which is the only seam the script offers for that binary.
                  programs._1password.enable = true;
                  security.wrapperDir = "${opStub}/bin";
                  programs.rclone.extended = {
                    enable = true;
                    protonDrive = {
                      enable = true;
                      authSource = "onePassword";
                      onePassword = {
                        usernameRef = "op://check/protondrive/username";
                        passwordRef = "op://check/protondrive/password";
                        otpRef = "op://check/protondrive/one-time password";
                        inherit mailboxPasswordRef;
                      };
                    };
                  };
                };
              };
            };

          activation = (mkHm { mailboxPasswordRef = ""; }).config.home.activation.configureRcloneConfig.data;

          # A two-password account. Kept separate because the ref is what
          # decides between opting out and reading a field that must not be
          # blank, and that is exactly the distinction under test.
          mailboxActivation =
            (mkHm { mailboxPasswordRef = "op://check/protondrive/mailbox"; })
            .config.home.activation.configureRcloneConfig.data;

          # RFC 4226 R6 puts the shared secret at 128 bits; this is the 160-bit
          # base32 shape Proton issues.
          seed = "MFRGGZDFMZTWQ2LKNNWG23TPOBYXE43U";
        in
        pkgs.runCommand "rclone-protondrive-otp-check"
          {
            passthru.runtimeCheck = true;
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.shellcheck
            ];
          }
          ''
            set -o errexit -o nounset -o pipefail

            check_root=${lib.escapeShellArg root}
            rendered=${lib.escapeShellArg "${root}/config/rclone/rclone.conf"}
            seed=${lib.escapeShellArg seed}

            # Every path here is fixed at eval time, so without the sandbox's
            # private /tmp another user could plant the root and have the
            # activation script's mkdir and writes follow its symlinks. mkdir
            # fails on an existing directory or symlink, which also catches
            # leftover state from an earlier unsandboxed run.
            if ! mkdir -m 700 -- "$check_root" 2>/dev/null; then
              echo "hm-apps/rclone-protondrive-otp: $check_root already exists; this check needs the sandbox's private /tmp" >&2
              exit 1
            fi
            trap 'rm -rf -- "$check_root"' EXIT

            export HOME="$check_root/home"
            mkdir -p "$HOME"

            cat > "$check_root/activation.sh" <<'ACTIVATION_EOF'
            ${activation}
            ACTIVATION_EOF

            cat > "$check_root/activation-mailbox.sh" <<'MAILBOX_ACTIVATION_EOF'
            ${mailboxActivation}
            MAILBOX_ACTIVATION_EOF

            # writeShellApplication lints the sync script, but an activation
            # entry is a raw string that nothing lints, which is how this branch
            # grew to its current size unchecked. SC1090 is excluded because
            # both env files it names are resolved at run time by design.
            shellcheck --shell=bash --severity=warning --exclude=SC1090 \
              "$check_root/activation.sh" "$check_root/activation-mailbox.sh"

            fail() {
              echo "hm-apps/rclone-protondrive-otp: $1" >&2
              exit 1
            }

            # Home Manager defines run for its activation scripts; nothing here
            # exercises its dry-run behaviour, so pass the command through.
            run_activation_keeping_config() {
              rc=0
              (
                run() { "$@"; }
                . "$check_root/activation.sh"
              ) > "$check_root/stdout" 2> "$check_root/stderr" || rc=$?
              printf '%s' "$rc"
            }

            run_activation() {
              rm -rf -- "$check_root/config"
              run_activation_keeping_config
            }

            run_mailbox_activation() {
              rm -rf -- "$check_root/config"
              rc=0
              (
                run() { "$@"; }
                . "$check_root/activation-mailbox.sh"
              ) > "$check_root/stdout" 2> "$check_root/stderr" || rc=$?
              printf '%s' "$rc"
            }

            # A seed pasted verbatim into the 1Password field, which is what op
            # read returns when the operator did not store an otpauth:// URI.
            rc=$(OP_STUB_OTP="$seed" run_activation)
            [ "$rc" -eq 0 ] || fail "a bare base32 seed must not fail activation (exit $rc)"
            grep -qxF "otp_secret_key = obscured:$seed" "$rendered" ||
              fail "a bare base32 seed must render otp_secret_key"

            # 1Password renders the field as this URI when the operator stored a
            # full otpauth:// value; the seed must come back identical.
            rc=$(OP_STUB_OTP="otpauth://totp/Proton:me?secret=$seed&issuer=Proton" run_activation)
            [ "$rc" -eq 0 ] || fail "an otpauth:// URI must not fail activation (exit $rc)"
            grep -qxF "otp_secret_key = obscured:$seed" "$rendered" ||
              fail "an otpauth:// URI must render the same otp_secret_key as its bare seed"

            # 1Password groups the printed seed for legibility; op read returns
            # the spacing verbatim.
            rc=$(OP_STUB_OTP="MFRG GZDF MZTW Q2LK NNWG 23TP OBYX E43U" run_activation)
            [ "$rc" -eq 0 ] || fail "a space-grouped seed must not fail activation (exit $rc)"
            grep -qxF "otp_secret_key = obscured:$seed" "$rendered" ||
              fail "a space-grouped seed must render the same otp_secret_key"

            # ?attribute=otp renders the current code instead of the seed.
            # Digits 2-7 are base32, so a code can satisfy a bare character-class
            # test on length alone; obscuring one yields a remote that cannot
            # authenticate and never says why.
            for code in 234567 123456 23456723; do
              rc=$(OP_STUB_OTP="$code" run_activation)
              [ "$rc" -ne 0 ] || fail "the rendered six-digit code $code must fail activation"
              grep -q 'OTP reference did not yield' "$check_root/stderr" ||
                fail "the rendered code $code must be rejected by the OTP diagnostic"
            done

            # A literal secret= outside the query string once matched the case
            # guard while failing the extraction, which left the seed empty,
            # kept the state at ready, and rendered a stanza with no
            # otp_secret_key rather than failing.
            rc=$(OP_STUB_OTP="otpauth://totp/xsecret=y" run_activation)
            [ "$rc" -ne 0 ] || fail "an otpauth:// URI whose secret= is not a query parameter must fail activation"
            [ ! -e "$rendered" ] ||
              ! grep -q '^\[protondrive\]$' "$rendered" ||
              fail "a rejected OTP value must not render a [protondrive] stanza"

            rc=$(OP_STUB_OTP="otpauth://totp/Proton:me?issuer=Proton" run_activation)
            [ "$rc" -ne 0 ] || fail "an otpauth:// URI with no secret= must fail activation"

            rc=$(OP_STUB_OTP="" run_activation)
            [ "$rc" -ne 0 ] || fail "an empty OTP value must fail activation while otpRef is set"

            # The lookup-failure branch gates whether the OTP parsing runs at
            # all, so it decides whether a locked vault reads as a transient
            # skip or as the configuration error that exits 1. Seed a good
            # config first, then lock the vault without clearing it.
            rc=$(OP_STUB_OTP="$seed" run_activation)
            [ "$rc" -eq 0 ] || fail "seeding the preserve path must succeed (exit $rc)"
            rc=$(OP_STUB_FAIL=1 run_activation_keeping_config)
            [ "$rc" -eq 0 ] || fail "an unavailable 1Password must not fail activation (exit $rc)"
            grep -qxF "otp_secret_key = obscured:$seed" "$rendered" ||
              fail "an unavailable 1Password must carry the previous stanza forward"
            grep -q 'credentials are unavailable' "$check_root/stderr" ||
              fail "an unavailable 1Password must warn"
            # The seed was never read, so reporting it as malformed would turn a
            # transient lock into a failed switch.
            ! grep -q 'OTP reference did not yield' "$check_root/stderr" ||
              fail "an unavailable 1Password must not report an OTP validation failure"

            rc=$(OP_STUB_FAIL=1 run_activation)
            [ "$rc" -eq 0 ] ||
              fail "an unavailable 1Password with nothing to preserve must not fail activation (exit $rc)"
            ! grep -q '^\[protondrive\]$' "$rendered" ||
              fail "an unavailable 1Password with nothing to preserve must not render a stanza"

            # The backend writes these into the stanza after a login, and Proton
            # rate-limits repeated logins, so they must survive an activation
            # that changed nothing. obscure draws a random IV per call, which is
            # why the rendered ciphertext cannot be the comparison and a
            # fingerprint of the 1Password values stands in for it.
            rc=$(OP_STUB_OTP="$seed" run_activation)
            [ "$rc" -eq 0 ] || fail "seeding the session-preservation path must succeed (exit $rc)"
            printf 'client_uid = uid-1\nclient_access_token = tok-1\n' >> "$rendered"

            rc=$(OP_STUB_OTP="$seed" run_activation_keeping_config)
            [ "$rc" -eq 0 ] || fail "an unchanged credential set must not fail activation (exit $rc)"
            grep -qxF 'client_uid = uid-1' "$rendered" ||
              fail "an unchanged credential set must preserve the session keys"
            grep -qxF 'client_access_token = tok-1' "$rendered" ||
              fail "an unchanged credential set must preserve every session key"

            rc=$(OP_STUB_OTP="$seed" OP_STUB_PASSWORD=rotated run_activation_keeping_config)
            [ "$rc" -eq 0 ] || fail "a rotated password must not fail activation (exit $rc)"
            ! grep -q '^client_uid = ' "$rendered" ||
              fail "a rotated password must drop the session keys"

            # ?attribute=otp renders the code into the URI's own secret=, so
            # validating only the bare arm would let the same six digits through
            # by the other shape.
            rc=$(OP_STUB_OTP="otpauth://totp/Proton:me?secret=234567&issuer=Proton" run_activation)
            [ "$rc" -ne 0 ] || fail "an otpauth:// URI carrying a rendered code must fail activation"
            rc=$(OP_STUB_OTP="otpauth://totp/Proton:me?secret=MFRG%3D&issuer=Proton" run_activation)
            [ "$rc" -ne 0 ] || fail "an otpauth:// URI whose secret= is not decodable base32 must fail activation"

            # A configured mailboxPasswordRef that reads back blank would
            # otherwise render a stanza that authenticates and then cannot
            # decrypt. Opting out is an empty ref, which never reaches op read.
            rc=$(OP_STUB_OTP="$seed" OP_STUB_MAILBOX=mailbox-secret run_mailbox_activation)
            [ "$rc" -eq 0 ] || fail "a populated mailbox reference must not fail activation (exit $rc)"
            grep -qxF 'mailbox_password = obscured:mailbox-secret' "$rendered" ||
              fail "a populated mailbox reference must render mailbox_password"

            rc=$(OP_STUB_OTP="$seed" OP_STUB_MAILBOX="" run_mailbox_activation)
            [ "$rc" -ne 0 ] || fail "a blank mailbox reference must fail activation"
            ! grep -q '^\[protondrive\]$' "$rendered" ||
              fail "a blank mailbox reference must not render a stanza"

            touch "$out"
          '';
    };
}
