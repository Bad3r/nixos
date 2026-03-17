/*
  Package: pwgen
  Description: Password generator which creates passwords which can be easily memorized by a human.
  Homepage: https://github.com/tytso/pwgen
  Documentation: https://github.com/tytso/pwgen
  Repository: https://github.com/tytso/pwgen

  Summary:
    * Generates random passwords and passphrases with configurable entropy and character classes.
    * Supports both pronounceable output and fully random strings for account and secret rotation workflows.

  Options:
    -s: Generate completely random, hard-to-memorize passwords.
    -y: Include at least one special character in each password.
    -B: Avoid ambiguous characters such as 0, O, 1, l, and I.
*/
_:
let
  PwgenModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pwgen.extended;
    in
    {
      options.programs.pwgen.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pwgen.";
        };

        package = lib.mkPackageOption pkgs "pwgen" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.pwgen = PwgenModule;
}
