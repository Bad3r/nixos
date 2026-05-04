/*
  Package: masscan
  Description: Fast scan of the Internet using a custom asynchronous TCP/IP stack.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/robertdavidgraham/masscan

  Summary:
    * Mass IP port scanner that produces results similar to nmap but is built for transmitting at line rate against large address ranges.
    * Supports banner grabbing, exclude lists, resumable scans, and XML/grepable/JSON output suitable for downstream tooling.

  Options:
    -p <ports>: Restrict the scan to the specified ports or port ranges (e.g. `-p80,443`, `-p0-65535`).
    --rate <pps>: Cap the transmit rate in packets per second.
    --banners: Grab banners after a successful TCP handshake (requires raw sockets).
    --exclude <ranges>: Skip the given IP ranges; pairs with `--excludefile` for large lists.
    -oX/-oG/-oJ <file>: Emit results in XML, grepable, or JSON format respectively.
    --resume <paused.conf>: Resume a previously interrupted scan from its checkpoint file.
*/
_:
let
  MasscanModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.masscan.extended;
    in
    {
      options.programs.masscan.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable masscan.";
        };

        package = lib.mkPackageOption pkgs "masscan" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.masscan = MasscanModule;
}
