/*
  Package: rclone
  Description: Command-line program to sync files and directories to cloud storage providers.
  Homepage: https://rclone.org/
  Documentation: https://rclone.org/docs/
  Repository: https://github.com/rclone/rclone

  Summary:
    * Synchronizes directories across over 70 cloud storage and S3-compatible providers with checksum verification.
    * Offers advanced features such as encryption, caching, chunked transfers, mounts, and HTTP serving.

  Options:
    --config <path>: Point rclone at an alternate configuration file containing remote definitions.
    --drive-server-side-across-configs: Enable server-side copies between Google Drive remotes when credentials permit.
    --transfers <n>: Limit the number of concurrent transfers to control bandwidth usage.
*/
_:
let
  RcloneModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      secretsRoot,
      ...
    }:
    let
      cfg = config.programs.rclone.extended;
      owner = metaOwner.username;
      gdriveSecretFile = secretsRoot + "/rclone_gdrive.env";
      gdriveSecretExists = builtins.pathExists gdriveSecretFile;
      gdriveSecretPath = "/run/secrets/rclone/gdrive-env";
      protondriveSecretFile = secretsRoot + "/rclone_protondrive.env";
      protondriveSecretExists = builtins.pathExists protondriveSecretFile;
      protondriveSecretPath = "/run/secrets/rclone/protondrive-env";
      repoSecretsEnabled = lib.attrByPath [ "security" "repoSecrets" "enable" ] true config;
    in
    {
      options.programs.rclone.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable rclone.";
        };

        package = lib.mkPackageOption pkgs "rclone" { };

        protonDrive = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to enable the Proton Drive rclone integration.";
          };

          authSource = lib.mkOption {
            type = lib.types.enum [
              "sops"
              "onePassword"
            ];
            default = "onePassword";
            description = "Credential source for the Proton Drive rclone remote.";
          };

          # No defaults here: this module is shared by every host, and a
          # non-empty default would make every host with protonDrive.enable
          # and the default authSource shell out to `op read` against one
          # specific person's vault. The owning host/user sets these (see
          # modules/hosts/common/rclone-protondrive-1password.nix), matching
          # the secretsRoot-gated pattern the sops authSource branch above
          # already uses for the same reason.
          onePassword = {
            usernameRef = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "1Password secret reference for the Proton username.";
            };

            passwordRef = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "1Password secret reference for the Proton login password.";
            };

            otpRef = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = ''
                1Password secret reference for the OTP field, or "" if the
                account has no 2FA enabled. The reference must return the
                otpauth:// URI, without the ?attribute=otp query, so the
                stable seed can be extracted and rclone can generate codes.
              '';
            };

            mailboxPasswordRef = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "1Password secret reference for the Proton mailbox password, or \"\" on a single-password account.";
            };
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];
        })

        (lib.mkIf (cfg.enable && cfg.protonDrive.enable && cfg.protonDrive.authSource == "onePassword") {
          assertions = [
            {
              assertion =
                lib.hasPrefix "op://" cfg.protonDrive.onePassword.usernameRef
                && lib.hasPrefix "op://" cfg.protonDrive.onePassword.passwordRef
                && lib.all (ref: ref == "" || lib.hasPrefix "op://" ref) [
                  cfg.protonDrive.onePassword.otpRef
                  cfg.protonDrive.onePassword.mailboxPasswordRef
                ];
              message = "programs.rclone.extended.protonDrive.authSource = \"onePassword\" requires non-empty op:// references for usernameRef and passwordRef. otpRef and mailboxPasswordRef are per-account optional (2FA / two-password accounts only): leave empty to opt out, or set an op:// reference.";
            }
            {
              assertion = config.programs._1password.enable;
              message = "programs.rclone.extended.protonDrive.authSource = \"onePassword\" resolves its op:// references during Home Manager activation, which needs the setgid ${config.security.wrapperDir}/op wrapper declared by programs._1password: the 1Password desktop app authorizes CLI integration by the caller's onepassword-cli group, and no user is a member of it directly. Enable programs.\"1password-cli\".extended or set authSource = \"sops\".";
            }
          ];
        })

        (lib.mkIf (cfg.enable && gdriveSecretExists && repoSecretsEnabled) {
          sops.secrets."rclone/gdrive-env" = {
            sopsFile = gdriveSecretFile;
            format = "dotenv";
            path = gdriveSecretPath;
            inherit owner;
            mode = "0400";
          };
        })

        (lib.mkIf (cfg.enable && gdriveSecretExists && (!repoSecretsEnabled)) {
          warnings = [
            "programs.rclone.extended.enable is true and ${toString gdriveSecretFile} exists, but security.repoSecrets.enable is false on this host; skipping gdrive secret materialization. Manage rclone gdrive config manually or enable repo secrets after SOPS decryption is configured."
          ];
        })

        (lib.mkIf (cfg.enable && !gdriveSecretExists) {
          warnings = [
            "programs.rclone.extended.enable is true but ${toString gdriveSecretFile} is missing; skipping gdrive remote setup."
          ];
        })

        (lib.mkIf
          (
            cfg.enable
            && cfg.protonDrive.enable
            && cfg.protonDrive.authSource == "sops"
            && protondriveSecretExists
            && repoSecretsEnabled
          )
          {
            sops.secrets."rclone/protondrive-env" = {
              sopsFile = protondriveSecretFile;
              format = "dotenv";
              path = protondriveSecretPath;
              inherit owner;
              mode = "0400";
            };
          }
        )

        # Proton Drive is separately gated by protonDrive.enable. A missing SOPS
        # secret is valid while the 1Password source is selected, so only
        # surface the actionable case where SOPS is explicitly selected.
        (lib.mkIf
          (
            cfg.enable
            && cfg.protonDrive.enable
            && cfg.protonDrive.authSource == "sops"
            && protondriveSecretExists
            && (!repoSecretsEnabled)
          )
          {
            warnings = [
              "programs.rclone.extended.protonDrive.enable is true and ${toString protondriveSecretFile} exists, but security.repoSecrets.enable is false on this host; skipping protondrive secret materialization. Manage rclone protondrive config manually or enable repo secrets after SOPS decryption is configured."
            ];
          }
        )
      ];
    };
in
{
  flake.nixosModules.apps.rclone = RcloneModule;
}
