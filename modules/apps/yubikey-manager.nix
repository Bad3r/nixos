/*
  Package: yubikey-manager
  Description: Command line tool for configuring any YubiKey over all USB transports.
  Homepage: https://developers.yubico.com/yubikey-manager
  Documentation: https://developers.yubico.com/yubikey-manager
  Repository: https://github.com/Yubico/yubikey-manager

  Summary:
    * Configures YubiKey applications and transports from a single CLI.
    * Supports device selection, diagnostics, and per-application management for FIDO, OATH, OpenPGP, OTP, and PIV.

  Options:
    list: List connected YubiKeys.
    info: Show general information for the selected YubiKey.
    config: Enable or disable YubiKey applications and interfaces.
    fido: Manage the FIDO applications.
    openpgp: Manage the OpenPGP application.
    piv: Manage the PIV application.
    --device SERIAL: Select a specific YubiKey by serial number.
    --diagnose: Print diagnostic information useful for troubleshooting.
*/
_:
let
  YubikeyManagerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.yubikey-manager.extended;
    in
    {
      options.programs.yubikey-manager.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable yubikey-manager.";
        };

        package = lib.mkPackageOption pkgs "yubikey-manager" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.yubikey-manager = YubikeyManagerModule;
}
