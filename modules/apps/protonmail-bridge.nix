/*
  Package: protonmail-bridge
  Description: Headless Proton Mail Bridge daemon that exposes Proton Mail to local IMAP/SMTP clients.
  Homepage: https://proton.me/mail/bridge
  Documentation: https://proton.me/support/protonmail-bridge-install
  Repository: https://github.com/ProtonMail/proton-bridge

  Summary:
    * Translates Proton Mail's encrypted API into local IMAP on `127.0.0.1:1143` (STARTTLS) and SMTP on `127.0.0.1:1025` (STARTTLS).

  Notes:
    * Starts only in a graphical session.
    * First sign-in: run `protonmail-bridge --cli`, then `login`, then `info` for the mail client password.
*/
_:
let
  ProtonmailBridgeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services."protonmail-bridge".extended;
    in
    {
      options.services."protonmail-bridge".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable protonmail-bridge.";
        };

        package = lib.mkPackageOption pkgs "protonmail-bridge" { };

        path = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          example = lib.literalExpression "with pkgs; [ pass gnome-keyring ]";
          description = ''
            Extra derivations placed on the daemon's PATH. Defaults to an empty list because Bridge
            talks to the system Secret Service over D-Bus (libsecret) and needs no extra binaries;
            override when selecting a non-Secret-Service credential backend.
          '';
        };

        logLevel = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "panic"
              "fatal"
              "error"
              "warn"
              "info"
              "debug"
            ]
          );
          default = null;
          description = "Log level forwarded to services.protonmail-bridge.logLevel; null preserves upstream's `mkOptionDefault`.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.protonmail-bridge = lib.mkMerge [
          {
            enable = true;
            inherit (cfg) package path;
          }
          (lib.mkIf (cfg.logLevel != null) {
            inherit (cfg) logLevel;
          })
        ];
      };
    };
in
{
  flake.nixosModules.apps."protonmail-bridge" = ProtonmailBridgeModule;
}
