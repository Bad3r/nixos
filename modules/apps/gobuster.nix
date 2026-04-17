/*
  Package: gobuster
  Description: Go-based content, DNS, and virtual-host brute-forcing tool for web reconnaissance.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/OJ/gobuster

  Summary:
    * Enumerates directories, files, DNS subdomains, and virtual hosts using wordlists and concurrent requests.
    * Covers common web recon modes with simple output suited to scripting and CI pipelines.

  Options:
    gobuster dir -u <url> -w <wordlist>: Enumerate directories and files on a web target.
    gobuster dns -d <domain> -w <wordlist>: Brute-force DNS subdomains for a target zone.
    gobuster vhost -u <url> -w <wordlist>: Probe virtual hosts by varying the Host header.
*/
_:
let
  GobusterModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gobuster.extended;
    in
    {
      options.programs.gobuster.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gobuster.";
        };

        package = lib.mkPackageOption pkgs "gobuster" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gobuster = GobusterModule;
}
