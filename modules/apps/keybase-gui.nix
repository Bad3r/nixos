/*
  Package: keybase-gui
  Description: Keybase official GUI.
  Homepage: https://keybase.io/
  Documentation: https://book.keybase.io/docs
  Repository: https://github.com/keybase/client

  Summary:
    * Launches the Keybase desktop app for chat, teams, files, identity proofs, and device management.
    * Mounts KBFS at ~/keybase, since the nixpkgs launcher refuses to start without kbfsfuse.
*/
_:
let
  KeybaseGuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."keybase-gui".extended;
    in
    {
      options.programs."keybase-gui".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the Keybase desktop app.";
        };

        package = lib.mkPackageOption pkgs "keybase-gui" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        services.kbfs.enable = true;

        programs.keybase.extended.enable = lib.mkOverride 1050 true;
      };
    };
in
{
  flake.nixosModules.apps."keybase-gui" = KeybaseGuiModule;
}
