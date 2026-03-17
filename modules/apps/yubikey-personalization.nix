/*
  Package: yubikey-personalization
  Description: Library and command line tool to personalize YubiKeys.
  Homepage: https://developers.yubico.com/yubikey-personalization
  Documentation: https://developers.yubico.com/yubikey-personalization
  Repository: https://github.com/Yubico/yubikey-personalization

  Summary:
    * Programs YubiKey OTP, static password, OATH, and related personalization settings.
    * Can save or restore configuration blobs and apply slot-specific configuration flags.

  Options:
    -1: Program or change the first YubiKey configuration slot.
    -2: Program or change the second YubiKey configuration slot.
    -u: Update a configuration without overwriting the whole slot.
    -sFILE: Save configuration data to a file or stdout.
    -iFILE: Read configuration data from a file or stdin.
    -oOPTION: Set configuration values or flags such as identities, access codes, or ticket behavior.
    -d: Perform a dry run without writing to the YubiKey.
*/
_:
let
  YubikeyPersonalizationModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.yubikey-personalization.extended;
    in
    {
      options.programs.yubikey-personalization.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable yubikey-personalization.";
        };

        package = lib.mkPackageOption pkgs "yubikey-personalization" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.yubikey-personalization = YubikeyPersonalizationModule;
}
