/*
  Package: nextcloud-client
  Description: Desktop sync client for Nextcloud.
  Homepage: https://nextcloud.com
  Documentation: https://docs.nextcloud.com/server/latest/user_manual/en/desktop/index.html
  Repository: https://github.com/nextcloud/desktop

  Summary:
    * Two-way syncs local folders against a Nextcloud server, with selective sync, virtual files, and per-folder bandwidth limits.
    * Ships the `nextcloud` tray GUI plus `nextcloudcmd`, a headless one-shot sync binary for scripted or cron-driven transfers.

  Options:
    --background: Start the GUI minimised to the tray instead of opening the main window.
    --confdir <dirname>: Read and write client state under an alternate configuration folder.
    --logdir <name>: Write one log file per sync run into the given folder (pairs with --logexpire).
    --serverurl <url>: Preseed the account wizard, or create an account non-interactively with --userid and --apppassword.
    -q, --quit: Terminate the running instance, which is what the user unit issues on stop.

  Notes:
    * Uses the services namespace because the client runs as a background sync daemon; modules/hm-apps/nextcloud-client.nix drives the Home Manager user unit.
    * HM services.nextcloud-client only references the package from its unit's ExecStart and never adds it to home.packages, so this module owns installation and the desktop entry.
    * Account credentials go to the Secret Service over libsecret; modules/hosts/common/gnome-keyring.nix already provides the backing daemon.
*/
_:
let
  NextcloudClientModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services."nextcloud-client".extended;
    in
    {
      options.services."nextcloud-client".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nextcloud-client.";
        };

        package = lib.mkPackageOption pkgs "nextcloud-client" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."nextcloud-client" = NextcloudClientModule;
}
