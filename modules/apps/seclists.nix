/*
  Package: seclists
  Description: Comprehensive wordlist and payload corpus used during security assessments.
  Repository: https://github.com/danielmiessler/SecLists

  Summary:
    * Installs the full SecLists dataset covering discovery, fuzzing, usernames, passwords, payloads, and miscellaneous recon inputs.
    * Provides a shared local corpus that can be referenced by tools such as feroxbuster, gobuster, hydra, and ffuf-style workflows.

  Notes:
    * Data only, at `/run/current-system/sw/share/wordlists/seclists`.
*/
_:
let
  SeclistsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.seclists.extended;
    in
    {
      options.programs.seclists.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable seclists.";
        };

        package = lib.mkPackageOption pkgs "seclists" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.seclists = SeclistsModule;
}
