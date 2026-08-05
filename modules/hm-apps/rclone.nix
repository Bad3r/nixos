/*
  Package: rclone
  Description: Command-line cloud storage sync utility supporting many providers.
  Homepage: https://rclone.org/
*/

_: {
  flake.homeManagerModules.apps.rclone =
    {
      config,
      osConfig,
      lib,
      pkgs,
      secretsRoot,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "rclone" "extended" "enable" ] false osConfig;
      gdriveSecretFile = secretsRoot + "/rclone_gdrive.env";
      gdriveSecretExists = builtins.pathExists gdriveSecretFile;
      gdriveEnvPath = lib.attrByPath [ "sops" "secrets" "rclone/gdrive-env" "path" ] null osConfig;
      repoSecretsEnabled = lib.attrByPath [ "security" "repoSecrets" "enable" ] true osConfig;
      gdriveSecretContents = if gdriveSecretExists then builtins.readFile gdriveSecretFile else "";
      gdriveTokenExists = lib.hasInfix "GDRIVE_TOKEN=" gdriveSecretContents;
      gdriveReady = gdriveSecretExists && repoSecretsEnabled && gdriveEnvPath != null;
      protondriveSecretFile = secretsRoot + "/rclone_protondrive.env";
      protondriveSecretExists = builtins.pathExists protondriveSecretFile;
      protondriveEnvPath = lib.attrByPath [
        "sops"
        "secrets"
        "rclone/protondrive-env"
        "path"
      ] null osConfig;
      protondriveAuth =
        lib.attrByPath
          [
            "programs"
            "rclone"
            "extended"
            "protonDrive"
          ]
          {
            enable = false;
            authSource = "sops";
            onePassword = {
              usernameRef = "";
              passwordRef = "";
              otpRef = "";
              mailboxPasswordRef = "";
            };
          }
          osConfig;
      protondriveOnePassword = protondriveAuth.onePassword or { };
      # otp_secret_key and mailbox_password are per-account optional (2FA /
      # two-password accounts only), so an empty ref opts out instead of
      # failing readiness; a non-empty ref still must be an op:// reference.
      protondriveOptionalRefValid = ref: ref == "" || lib.hasPrefix "op://" ref;
      protondriveOnePasswordReady =
        protondriveAuth.enable
        && protondriveAuth.authSource == "onePassword"
        && lib.hasPrefix "op://" (protondriveOnePassword.usernameRef or "")
        && lib.hasPrefix "op://" (protondriveOnePassword.passwordRef or "")
        && protondriveOptionalRefValid (protondriveOnePassword.otpRef or "")
        && protondriveOptionalRefValid (protondriveOnePassword.mailboxPasswordRef or "");
      protondriveSopsSelected = protondriveAuth.enable && protondriveAuth.authSource == "sops";
      protondriveSopsReady =
        protondriveSopsSelected
        && protondriveSecretExists
        && repoSecretsEnabled
        && protondriveEnvPath != null;
      protondriveReady = protondriveSopsReady || protondriveOnePasswordReady;
      r2SecretFile = secretsRoot + "/r2.yaml";
      r2SecretExists = builtins.pathExists r2SecretFile;
      r2SecretsEnabled = lib.attrByPath [ "home" "r2Secrets" "enable" ] false config;
      r2EndpointAvailable = r2SecretsEnabled && r2SecretExists;
      renderedRcloneConfig = "${config.xdg.configHome}/rclone/rclone.conf";
      rclonePackage = lib.attrByPath [ "programs" "rclone" "package" ] pkgs.rclone config;
      rcloneExecutable = lib.getExe' rclonePackage "rclone";
      # The 1Password desktop app authorizes CLI integration by the caller's
      # effective onepassword-cli group, which only the setgid wrapper from
      # programs._1password carries; the plain package binary runs without it
      # and every op read fails. modules/apps/rclone.nix asserts the wrapper
      # exists whenever the op:// source is selected.
      onePasswordEnabled = lib.attrByPath [ "programs" "_1password" "enable" ] false osConfig;
      onePasswordWrapperDir = lib.attrByPath [ "security" "wrapperDir" ] "/run/wrappers/bin" osConfig;
      onePasswordExecutable =
        if onePasswordEnabled then "${onePasswordWrapperDir}/op" else lib.getExe' pkgs._1password-cli "op";
      # Ownership guard inputs. The r2-flake Home Manager module declares
      # programs.r2-cloud only when a host policy imports it, so probe with
      # attrByPath instead of reading undeclared options.
      r2CloudCfg = lib.attrByPath [ "programs" "r2-cloud" ] { } config;
      r2CloudRcloneConfigPath =
        if r2CloudCfg ? rcloneConfigPath then toString r2CloudCfg.rcloneConfigPath else "";
      r2CloudClaimsRenderedConfig =
        (r2CloudCfg.enable or false)
        && (r2CloudCfg.enableRcloneRemote or false)
        && r2CloudRcloneConfigPath == renderedRcloneConfig;
    in
    {
      config = lib.mkIf nixosEnabled (
        lib.mkMerge [
          {
            # This module is the single writer of renderedRcloneConfig while
            # programs.rclone.extended.enable is set; other generators must
            # target a different path (see docs/r2-cloud/home-manager-r2-cloud.md).
            assertions = [
              {
                assertion = !r2CloudClaimsRenderedConfig;
                message = "programs.rclone.extended.enable makes modules/hm-apps/rclone.nix the owner of ${renderedRcloneConfig}, but programs.r2-cloud.enableRcloneRemote also renders programs.r2-cloud.rcloneConfigPath = ${r2CloudRcloneConfigPath}. Set programs.r2-cloud.enableRcloneRemote = false (as modules/lib/r2-runtime.nix does) or point programs.r2-cloud.rcloneConfigPath at a different file.";
              }
              {
                assertion = config.programs.rclone.remotes == { };
                message = "programs.rclone.remotes would make the upstream Home Manager rclone-config generator a second writer of ${renderedRcloneConfig} next to the activation writer in modules/hm-apps/rclone.nix. Keep remotes empty or retire the activation writer first.";
              }
            ];

            programs.rclone = {
              enable = true;
            };

            home.activation.configureRcloneConfig = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
              renderedConfig=${lib.escapeShellArg renderedRcloneConfig}
              renderedDir="$(dirname "$renderedConfig")"
              protondriveFingerprintFile="$renderedDir/protondrive-credentials.fingerprint"
              endpointFile=${
                lib.escapeShellArg (
                  if r2EndpointAvailable then config.sops.templates."rclone/r2-endpoint".path else ""
                )
              }
              gdriveEnabled=${lib.boolToString gdriveReady}
              gdriveEnvPath=${lib.escapeShellArg (if gdriveReady then gdriveEnvPath else "")}
              protondriveEnabled=${lib.boolToString protondriveReady}
              protondriveEnvPath=${lib.escapeShellArg (if protondriveSopsReady then protondriveEnvPath else "")}
              protondriveAuthSource=${lib.escapeShellArg protondriveAuth.authSource}
              protondriveUsernameRef=${lib.escapeShellArg (protondriveOnePassword.usernameRef or "")}
              protondrivePasswordRef=${lib.escapeShellArg (protondriveOnePassword.passwordRef or "")}
              protondriveOtpRef=${lib.escapeShellArg (protondriveOnePassword.otpRef or "")}
              protondriveMailboxPasswordRef=${
                lib.escapeShellArg (protondriveOnePassword.mailboxPasswordRef or "")
              }
              opExecutable=${lib.escapeShellArg onePasswordExecutable}
              rcloneExecutable=${lib.escapeShellArg rcloneExecutable}

              run mkdir -p "$renderedDir"
              chmod 700 "$renderedDir"
              tmpConfig="$(mktemp "$renderedDir/rclone.conf.XXXXXX")"
              trap 'rm -f "$tmpConfig"' EXIT

              {
                printf '[r2]\n'
                printf 'type = s3\n'
                printf 'provider = Cloudflare\n'
                printf 'env_auth = true\n'
                if [ -n "$endpointFile" ] && [ -r "$endpointFile" ]; then
                  printf 'endpoint = %s\n' "$(cat "$endpointFile")"
                fi
              } > "$tmpConfig"

              if [ "$gdriveEnabled" = true ]; then
                # The sops secret may not be materialized yet on a first
                # activation; skip with a warning instead of aborting the
                # whole home-manager activation under set -eu.
                if [ ! -r "$gdriveEnvPath" ]; then
                  echo "rclone gdrive env file is missing or unreadable at $gdriveEnvPath; skipping gdrive remote refresh for this activation" >&2
                  # Carry the previously rendered [gdrive] stanza forward so a
                  # transiently unreadable secret does not drop a working
                  # remote from the rewritten config.
                  if [ -r "$renderedConfig" ]; then
                    prevGdrive="$(sed -n '/^\[gdrive\]$/,/^\[/{ /^\[gdrive\]$/p; /^\[/!p; }' "$renderedConfig")"
                    if [ -n "$prevGdrive" ]; then
                      printf '\n%s\n' "$prevGdrive" >> "$tmpConfig"
                      echo "rclone gdrive remote preserved from the previous rendered config" >&2
                    fi
                  fi
                else
                  unset GDRIVE_CLIENT_ID GDRIVE_CLIENT_SECRET GDRIVE_TOKEN
                  . "$gdriveEnvPath"

                  if [ -z "''${GDRIVE_CLIENT_ID:-}" ] || [ -z "''${GDRIVE_CLIENT_SECRET:-}" ]; then
                    echo "rclone gdrive env file is missing GDRIVE_CLIENT_ID or GDRIVE_CLIENT_SECRET: $gdriveEnvPath" >&2
                    exit 1
                  fi

                  {
                    printf '\n[gdrive]\n'
                    printf 'type = drive\n'
                    printf 'client_id = %s\n' "$GDRIVE_CLIENT_ID"
                    printf 'client_secret = %s\n' "$GDRIVE_CLIENT_SECRET"
                    printf 'scope = drive\n'
                    if [ -n "''${GDRIVE_TOKEN:-}" ]; then
                      printf 'token = %s\n' "$GDRIVE_TOKEN"
                    fi
                  } >> "$tmpConfig"
                fi
              fi

              if [ "$protondriveEnabled" = true ]; then
                protondriveCredentialsState=unavailable
                protondriveCredentialMaterial=""
                unset PROTONDRIVE_USERNAME PROTONDRIVE_PASSWORD PROTONDRIVE_OTP_SECRET_KEY PROTONDRIVE_MAILBOX_PASSWORD

                if [ "$protondriveAuthSource" = onePassword ]; then
                  protondriveLookupFailed=0
                  protondriveUsernameRaw=""
                  protondrivePasswordRaw=""
                  protondriveOtpUri=""
                  protondriveOtpSeed=""
                  protondriveMailboxPasswordRaw=""
                  # A locked desktop app raises an unlock/biometric prompt and
                  # blocks op read until it is answered; time out instead of
                  # stalling activation, and let the existing failure path
                  # below take the warn-and-preserve branch.
                  protondriveUsernameRaw="$(timeout 30 "$opExecutable" read --no-newline "$protondriveUsernameRef")" || protondriveLookupFailed=1
                  protondrivePasswordRaw="$(timeout 30 "$opExecutable" read --no-newline "$protondrivePasswordRef")" || protondriveLookupFailed=1
                  # otp_secret_key and mailbox_password are per-account optional
                  # (2FA / two-password accounts only), so an empty configured
                  # ref opts out instead of being read.
                  if [ -n "$protondriveOtpRef" ]; then
                    protondriveOtpUri="$(timeout 30 "$opExecutable" read --no-newline "$protondriveOtpRef")" || protondriveLookupFailed=1
                  fi
                  if [ -n "$protondriveMailboxPasswordRef" ]; then
                    protondriveMailboxPasswordRaw="$(timeout 30 "$opExecutable" read --no-newline "$protondriveMailboxPasswordRef")" || protondriveLookupFailed=1
                  fi

                  if [ "$protondriveLookupFailed" -eq 0 ]; then
                    if [ -n "$protondriveOtpRef" ]; then
                      case "$protondriveOtpUri" in
                        otpauth://*)
                          protondriveOtpSeed="$(printf '%s\n' "$protondriveOtpUri" | sed -n 's/.*[?&]secret=\([^&]*\).*/\1/p')"
                          ;;
                        *)
                          # 1Password stores the one-time password field
                          # verbatim, which is commonly the bare base32 seed
                          # rather than an otpauth:// URI. Digits 2-7 are base32,
                          # so a rendered code passes a bare character test; the
                          # length floor is what separates the two (RFC 4226 R6
                          # puts the shared secret at 128 bits, and no TOTP seed
                          # is under the 16 characters of an 80-bit one).
                          protondriveOtpSeed="$(printf '%s' "$protondriveOtpUri" | tr -d ' ' | sed -n '/^[A-Za-z2-7]\{16,\}=*$/p')"
                          ;;
                      esac
                      if [ -z "$protondriveOtpSeed" ]; then
                        echo "rclone protondrive 1Password OTP reference returned neither an otpauth:// URI with a secret= parameter nor a bare base32 seed; it must hold the stable TOTP seed, not the rendered six-digit code" >&2
                        protondriveCredentialsState=invalid
                      fi
                    fi

                    if [ -z "$protondriveUsernameRaw" ] || [ -z "$protondrivePasswordRaw" ]; then
                      echo "rclone protondrive 1Password references returned an empty username or password" >&2
                      protondriveCredentialsState=invalid
                    fi

                    if [ "$protondriveCredentialsState" != invalid ]; then
                      PROTONDRIVE_USERNAME="$protondriveUsernameRaw"
                      PROTONDRIVE_PASSWORD="$(printf '%s\n' "$protondrivePasswordRaw" | "$rcloneExecutable" obscure -)" || protondriveCredentialsState=invalid
                      if [ -n "$protondriveOtpSeed" ]; then
                        PROTONDRIVE_OTP_SECRET_KEY="$(printf '%s\n' "$protondriveOtpSeed" | "$rcloneExecutable" obscure -)" || protondriveCredentialsState=invalid
                      fi
                      if [ -n "$protondriveMailboxPasswordRaw" ]; then
                        PROTONDRIVE_MAILBOX_PASSWORD="$(printf '%s\n' "$protondriveMailboxPasswordRaw" | "$rcloneExecutable" obscure -)" || protondriveCredentialsState=invalid
                      fi
                      # rclone obscure draws a fresh random IV per call, so the
                      # ciphertexts above differ on every activation. Fingerprint
                      # the stable 1Password values instead.
                      protondriveCredentialMaterial="$(printf '%s\n%s\n%s\n%s' "$protondriveUsernameRaw" "$protondrivePasswordRaw" "$protondriveOtpSeed" "$protondriveMailboxPasswordRaw")"
                      if [ "$protondriveCredentialsState" != invalid ]; then
                        protondriveCredentialsState=ready
                      fi
                    fi
                  fi

                  if [ "$protondriveLookupFailed" -ne 0 ]; then
                    echo "rclone protondrive 1Password credentials are unavailable; skipping protondrive remote refresh for this activation" >&2
                  fi
                else
                  # The SOPS secret may be unmaterialized on a first activation,
                  # so preserve a working remote instead of aborting activation.
                  if [ ! -r "$protondriveEnvPath" ]; then
                    echo "rclone protondrive env file is missing or unreadable at $protondriveEnvPath; skipping protondrive remote refresh for this activation" >&2
                  else
                    . "$protondriveEnvPath"

                    if [ -z "''${PROTONDRIVE_USERNAME:-}" ] || [ -z "''${PROTONDRIVE_PASSWORD:-}" ]; then
                      echo "rclone protondrive env file is missing PROTONDRIVE_USERNAME or PROTONDRIVE_PASSWORD: $protondriveEnvPath" >&2
                      protondriveCredentialsState=invalid
                    else
                      # Already obscured in the secret, so these are stable.
                      protondriveCredentialMaterial="$(printf '%s\n%s\n%s\n%s' "$PROTONDRIVE_USERNAME" "$PROTONDRIVE_PASSWORD" "''${PROTONDRIVE_OTP_SECRET_KEY:-}" "''${PROTONDRIVE_MAILBOX_PASSWORD:-}")"
                      protondriveCredentialsState=ready
                    fi
                  fi
                fi

                if [ "$protondriveCredentialsState" = invalid ]; then
                  exit 1
                elif [ "$protondriveCredentialsState" = ready ]; then
                  # The protondrive backend persists reusable login credentials
                  # in the remote stanza after authentication. Preserve only
                  # those backend-owned keys when every login credential is
                  # unchanged; dropping them forces a fresh Proton login, and
                  # Proton rate-limits repeated logins.
                  prevProtonSession=""
                  protondriveFingerprint="$(printf '%s' "$protondriveCredentialMaterial" | sha256sum | cut -d' ' -f1)"
                  if
                    [ -r "$protondriveFingerprintFile" ] && [ -r "$renderedConfig" ] &&
                      [ "$(cat "$protondriveFingerprintFile")" = "$protondriveFingerprint" ]
                  then
                    prevProtonSession="$(sed -n '/^\[protondrive\]$/,/^\[/{ /^client_uid *=/p; /^client_access_token *=/p; /^client_refresh_token *=/p; /^client_salted_key_pass *=/p; }' "$renderedConfig")"
                  fi

                  # password/otp_secret_key/mailbox_password are rclone-obscured;
                  # the backend reveals them. enable_caching is forced off because
                  # Proton's change-event system is unimplemented.
                  {
                    printf '\n[protondrive]\n'
                    printf 'type = protondrive\n'
                    printf 'username = %s\n' "$PROTONDRIVE_USERNAME"
                    printf 'password = %s\n' "$PROTONDRIVE_PASSWORD"
                    if [ -n "''${PROTONDRIVE_OTP_SECRET_KEY:-}" ]; then
                      printf 'otp_secret_key = %s\n' "$PROTONDRIVE_OTP_SECRET_KEY"
                    fi
                    if [ -n "''${PROTONDRIVE_MAILBOX_PASSWORD:-}" ]; then
                      printf 'mailbox_password = %s\n' "$PROTONDRIVE_MAILBOX_PASSWORD"
                    fi
                    if [ -n "$prevProtonSession" ]; then
                      printf '%s\n' "$prevProtonSession"
                    fi
                    printf 'enable_caching = false\n'
                  } >> "$tmpConfig"
                else
                  # Carry the previous stanza forward when 1Password is locked or
                  # a SOPS secret is unavailable during a transient activation.
                  if [ -r "$renderedConfig" ]; then
                    prevProton="$(sed -n '/^\[protondrive\]$/,/^\[/{ /^\[protondrive\]$/p; /^\[/!p; }' "$renderedConfig")"
                    if [ -n "$prevProton" ]; then
                      printf '\n%s\n' "$prevProton" >> "$tmpConfig"
                      echo "rclone protondrive remote preserved from the previous rendered config" >&2
                    fi
                  fi
                fi

                unset PROTONDRIVE_USERNAME PROTONDRIVE_PASSWORD PROTONDRIVE_OTP_SECRET_KEY PROTONDRIVE_MAILBOX_PASSWORD
                unset protondriveUsernameRaw protondrivePasswordRaw protondriveOtpUri protondriveOtpSeed protondriveMailboxPasswordRaw
                unset prevProtonSession protondriveCredentialMaterial
              fi

              chmod 600 "$tmpConfig"
              run mv "$tmpConfig" "$renderedConfig"

              if [ -n "''${protondriveFingerprint:-}" ]; then
                # A digest of the credentials, not the credentials: the config
                # beside it already carries their reversible obscured form.
                printf '%s\n' "$protondriveFingerprint" > "$protondriveFingerprintFile"
                chmod 600 "$protondriveFingerprintFile"
              fi
            '';
          }

          (lib.mkIf r2EndpointAvailable {
            sops.templates."rclone/r2-endpoint" = {
              content = ''
                https://${config.sops.placeholder."cloudflare/r2/account-id"}.r2.cloudflarestorage.com
              '';
              mode = "0400";
            };
          })

          (lib.mkIf (gdriveSecretExists && (!repoSecretsEnabled)) {
            warnings = [
              "programs.rclone.extended.enable is true and ${toString gdriveSecretFile} exists, but security.repoSecrets.enable is false on this host; skipping gdrive remote setup. Manage ~/.config/rclone/rclone.conf manually or enable repo secrets after SOPS decryption is configured."
            ];
          })

          (lib.mkIf (gdriveSecretExists && repoSecretsEnabled && gdriveEnvPath == null) {
            warnings = [
              "programs.rclone.extended.enable is true and ${toString gdriveSecretFile} exists, but no system-side rclone/gdrive-env secret path was declared in osConfig; skipping gdrive remote setup."
            ];
          })

          (lib.mkIf (gdriveSecretExists && !gdriveTokenExists) {
            warnings = [
              "rclone gdrive credentials were loaded from ${toString gdriveSecretFile}, but no GDRIVE_TOKEN was found. Obtain a Drive token with a temporary rclone config or `rclone authorize drive <client_id> <client_secret>`, then store the resulting JSON as GDRIVE_TOKEN in ${toString gdriveSecretFile}."
            ];
          })

          # Only the SOPS source needs the secret; under the 1Password source the
          # system side declares no rclone/protondrive-env path, so an ungated
          # warning fires while the remote renders fine.
          (lib.mkIf (protondriveSopsSelected && protondriveSecretExists && (!repoSecretsEnabled)) {
            warnings = [
              "programs.rclone.extended.protonDrive.authSource is \"sops\" and ${toString protondriveSecretFile} exists, but security.repoSecrets.enable is false on this host; skipping protondrive remote setup. Manage ~/.config/rclone/rclone.conf manually or enable repo secrets after SOPS decryption is configured."
            ];
          })

          (lib.mkIf
            (
              protondriveSopsSelected
              && protondriveSecretExists
              && repoSecretsEnabled
              && protondriveEnvPath == null
            )
            {
              warnings = [
                "programs.rclone.extended.protonDrive.authSource is \"sops\" and ${toString protondriveSecretFile} exists, but no system-side rclone/protondrive-env secret path was declared in osConfig; skipping protondrive remote setup."
              ];
            }
          )
        ]
      );
    };
}
