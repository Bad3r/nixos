/*
  Package: vulnix
  Description: NixOS vulnerability scanner.
  Homepage: https://github.com/nix-community/vulnix
  Documentation: https://github.com/nix-community/vulnix#readme
  Repository: https://github.com/nix-community/vulnix

  Summary:
    * Scans NixOS system, profiles, or GC roots against the NVD for known CVEs.
    * Supports TOML whitelists to suppress false positives from CPE name collisions.

  Options:
    -S: Scan the current system.
    -G: Scan all active GC roots (including old ones).
    -w: Load whitelist from file or URL (may be given multiple times).
    -W: Write TOML whitelist containing current matches.
    -j: JSON output instead of human-readable.
    -D: Show descriptions of vulnerabilities.

  Notes:
    * Every scan applies the repo whitelist (`whitelist.toml`).
*/
_:
let
  VulnixModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.vulnix.extended;
      wrappedVulnix = pkgs.symlinkJoin {
        name = "vulnix-wrapped";
        paths = [ cfg.package ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/vulnix \
            --add-flags "-w ${cfg.whitelistFile}"
        '';
      };
    in
    {
      options.programs.vulnix.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vulnix.";
        };

        package = lib.mkPackageOption pkgs "vulnix" { };

        whitelistFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = ./whitelist.toml;
          description = "Path to the TOML whitelist file for suppressing false-positive CVEs. Set to null to disable.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          (if cfg.whitelistFile != null then wrappedVulnix else cfg.package)
        ];
      };
    };
in
{
  flake.nixosModules.apps.vulnix = VulnixModule;
}
