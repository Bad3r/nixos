/*
  Package: keybase
  Description: Keybase official command-line utility and service.
  Homepage: https://keybase.io/
  Documentation: https://book.keybase.io/docs/cli
  Repository: https://github.com/keybase/client

  Summary:
    * Manages a Keybase identity, devices, proofs, chat, teams, and encrypted git from the command line.
    * Runs the Keybase service as a systemd user unit through the NixOS keybase module.

  Options:
    login: Provision this device for an existing Keybase account.
    status: Show the logged-in user, device, and service state.
    chat: Send and read Keybase chat messages.
    encrypt: Encrypt a message or file for Keybase users.
*/
_:
let
  KeybaseModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.keybase.extended;
    in
    {
      options.programs.keybase.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable keybase.";
        };

        package = lib.mkPackageOption pkgs "keybase" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        services.keybase.enable = true;
      };
    };
in
{
  flake.nixosModules.apps.keybase = KeybaseModule;
}
