/*
  Package: xkcdpass
  Description: Generate secure multiword passwords/passphrases, inspired by XKCD.
  Homepage: https://github.com/redacted/XKCD-password-generator
  Documentation: https://github.com/redacted/XKCD-password-generator
  Repository: https://github.com/redacted/XKCD-password-generator

  Summary:
    * Generates multiword passphrases from bundled or custom wordlists.
    * Supports length, word-count, acrostic, delimiter, and casing constraints for policy-driven output.

  Options:
    -w, --wordfile: Select one or more wordlists for passphrase generation.
    -n, --numwords: Generate passphrases with an exact number of words.
    -a, --acrostic: Generate passphrases whose initials match a target acrostic.
    -d, --delimiter: Set the delimiter used between words.
    -C, --case: Choose how each word is cased in the generated passphrase.
    --allow-weak-rng: Permit fallback to a weak random number generator when secure RNG is unavailable.
*/
_:
let
  XkcdpassModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xkcdpass.extended;
    in
    {
      options.programs.xkcdpass.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xkcdpass.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "xkcdpass" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xkcdpass = XkcdpassModule;
}
