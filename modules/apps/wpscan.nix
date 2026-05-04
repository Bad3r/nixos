/*
  Package: wpscan
  Description: Black box WordPress security scanner for identifying vulnerabilities, misconfigurations, and weak credentials.
  Homepage: https://wpscan.com/wordpress-cli-scanner/
  Documentation: https://github.com/wpscanteam/wpscan/wiki
  Repository: https://github.com/wpscanteam/wpscan

  Summary:
    * Enumerates WordPress core, themes, plugins, users, and exposed backups, correlating findings against the WPScan vulnerability database.
    * Performs authenticated scans, password brute-forcing against `xmlrpc.php` and `wp-login.php`, and HTTP fingerprinting through a configurable detection engine.

  Options:
    --url <url>: Target blog URL (HTTP or HTTPS); mandatory for scans.
    -e [opts]: Enumerate components (e.g. `vp,vt,u`: vulnerable plugins/themes and users).
    --plugins-detection <mode>: Plugin detection aggressiveness (`passive`, `mixed`, `aggressive`).
    --api-token <token>: Authenticate to the WPScan API for richer vulnerability metadata.
    -P <wordlist>: Password list for `--passwords` brute force; pair with `-U` for usernames.
    -U <users>: User list or comma-separated names to attempt during password attacks.
    -o <file> / -f <format>: Persist results to a file in `cli`, `cli-no-colour`, or `json` format.
    --random-user-agent: Randomize the User-Agent for each request to evade simple WAFs.

  Notes:
    * `pkgs.wpscan` ships under an unfree-redistributable license; entry below opts the package into `nixpkgs.allowedUnfreePackages`.
*/
_:
let
  WpscanModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wpscan.extended;
    in
    {
      options.programs.wpscan.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wpscan.";
        };

        package = lib.mkPackageOption pkgs "wpscan" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "wpscan" ];
  flake.nixosModules.apps.wpscan = WpscanModule;
}
