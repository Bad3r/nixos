/*
  Package: protonmail-bridge
  Description: Headless Proton Mail Bridge daemon that exposes Proton Mail to local IMAP/SMTP clients.
  Homepage: https://proton.me/mail/bridge
  Documentation: https://proton.me/support/protonmail-bridge-install
  Repository: https://github.com/ProtonMail/proton-bridge

  Summary:
    * Runs the upstream Bridge binary as a systemd user service in `--noninteractive` mode.
    * Translates Proton Mail's encrypted API into local IMAP on `127.0.0.1:1143` (STARTTLS) and SMTP on `127.0.0.1:1025` (STARTTLS).
    * Talks to the host's Secret Service implementation over D-Bus (libsecret), so any GNOME Keyring, KWallet, or `pass-secret-service` backend works without further configuration.
    * Upstream's user unit is gated on `graphical-session.target`, so the daemon only starts once a desktop session is active; on a headless host the unit will sit idle.

  Initial sign-in:
    The daemon runs with `--noninteractive` and cannot perform the first login. After enabling the
    module, run `protonmail-bridge --cli` interactively once, type `login` to complete the Proton
    flow, then `info` to print the per-account Bridge password. Paste that password into the mail
    client; the daemon picks up the stored credentials from the keyring on the next start.

  Example Usage:
    * Point Thunderbird (or any IMAP client) at `127.0.0.1`, IMAP `1143`, SMTP `1025`, both with STARTTLS, using the Bridge-generated password.
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
