/*
  Package: thunderbird
  Description: Full-featured e-mail client.
  Homepage: https://thunderbird.net/
  Documentation: https://support.mozilla.org/en-US/products/thunderbird
  Repository: https://hg.mozilla.org/comm-central/

  Summary:
    * Provides a desktop mail client with integrated calendar, contacts, tasks, and feed support.
    * Supports multiple profiles, OpenPGP key management, and add-on based customization.

  Options:
    -P <profile>: Start Thunderbird with a specific profile name.
    --ProfileManager: Open the profile manager to create/select profiles.
    --safe-mode: Start Thunderbird with extensions and themes disabled for troubleshooting.
    -compose [ <options> ]: Open a new compose window with prefilled message fields.
*/
_:
let
  ThunderbirdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.thunderbird.extended;
    in
    {
      options.programs.thunderbird.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable thunderbird.";
        };

        package = lib.mkPackageOption pkgs "thunderbird" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.thunderbird = ThunderbirdModule;
}
