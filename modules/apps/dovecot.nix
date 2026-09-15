/*
  Package: dovecot
  Description: Open source IMAP and POP3 email server written with security primarily in mind.
  Homepage: https://dovecot.org/
  Documentation: https://doc.dovecot.org/
  Repository: https://github.com/dovecot/core

  Summary:
    * Serves IMAP and POP3 mailbox access to local and remote mail clients, with LMTP delivery and ManageSieve filtering support.
    * Built with security as a primary design goal; commonly paired with an MTA such as Postfix for self-hosted mail storage.

  Notes:
    * Uses the services namespace because dovecot runs as a system service.
    * The upstream NixOS module keeps the historical `services.dovecot2` option name even though the package, systemd unit, and this module are all named `dovecot`.
    * Pins `services.dovecot2.settings.dovecot_config_version` and `dovecot_storage_version` to `cfg.package.version`, the value upstream's own assertion messages recommend, since Dovecot 2.4 fails evaluation without them set.
*/
_:
let
  DovecotModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.dovecot.extended;
    in
    {
      options.services.dovecot.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dovecot.";
        };

        package = lib.mkPackageOption pkgs "dovecot" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        services.dovecot2 = {
          enable = true;
          inherit (cfg) package;
          settings = {
            dovecot_config_version = cfg.package.version;
            dovecot_storage_version = cfg.package.version;
          };
        };
      };
    };
in
{
  flake.nixosModules.apps.dovecot = DovecotModule;
}
