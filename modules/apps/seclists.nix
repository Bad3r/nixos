/*
  Package: seclists
  Description: Comprehensive wordlist and payload corpus used during security assessments.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/danielmiessler/SecLists

  Summary:
    * Installs the full SecLists dataset covering discovery, fuzzing, usernames, passwords, payloads, and miscellaneous recon inputs.
    * Provides a shared local corpus that can be referenced by tools such as feroxbuster, gobuster, hydra, and ffuf-style workflows.

  Options:
    /run/current-system/sw/share/wordlists/seclists: Access the installed SecLists tree from the active system profile.
    Discovery/Web-Content/common.txt: Use a common starter list for directory and file enumeration.
    Passwords/Leaked-Databases/rockyou.txt.tar.gz: Reference the bundled archived password corpus for offline cracking workflows.

  Notes:
    * This is a data-only package; tools should reference files under `share/wordlists/seclists` rather than expecting a CLI binary.
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
