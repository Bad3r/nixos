/*
  Package: age-plugin-fido2prf
  Description: FIDO2 WebAuthn-backed identity plugin for age.
  Homepage: https://github.com/FiloSottile/typage
  Documentation: https://github.com/FiloSottile/typage
  Repository: https://github.com/FiloSottile/typage

  Summary:
    * Enables hardware-token age recipients without exposing long-lived private keys on disk.
*/
_:
let
  AgePluginFido2PrfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."age-plugin-fido2prf".extended;
    in
    {
      options.programs.age-plugin-fido2prf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable age-plugin-fido2prf.";
        };

        package = lib.mkPackageOption pkgs "age-plugin-fido2prf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.age-plugin-fido2prf = AgePluginFido2PrfModule;
}
