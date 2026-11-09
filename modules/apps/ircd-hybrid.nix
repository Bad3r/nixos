/*
  Package: ircd-hybrid
  Description: IPv6-capable IRC server daemon.
  Homepage: https://www.ircd-hybrid.org/
  Documentation: https://wiki.ircd-hybrid.org/
  Repository: https://github.com/ircd-hybrid/ircd-hybrid

  Summary:
    * Serves IRC clients and links with other servers, with TLS listeners, operator classes, and K-line, D-line, and X-line bans.
    * Ships `mkpasswd` for hashing operator passwords and a `reference.ircd.conf` starting point under etc/.

  Options:
    -c, --configfile <path>: Read ircd.conf from a specific file.
    -f, --foreground: Stay in the foreground instead of detaching.
    -l, --logfile <path>: Write the server log to a specific file.
    -p, --pidfile <path>: Write the process ID to a specific file.
    -v, --version: Print the version and exit.

  Notes:
    * The package is installed; no service unit is defined, and `services.ircdHybrid` stays off.
*/
_:
let
  IrcdHybridModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."ircd-hybrid".extended;
    in
    {
      options.programs."ircd-hybrid".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ircd-hybrid.";
        };

        package = lib.mkPackageOption pkgs "ircd-hybrid" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."ircd-hybrid" = IrcdHybridModule;
}
