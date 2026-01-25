/*
  Package: nicotine-plus
  Description: GTK-based Soulseek client for file sharing and community chat.
  Homepage: https://nicotine-plus.org/
  Documentation: https://nicotine-plus.github.io/nicotine-plus/
  Repository: https://github.com/nicotine-plus/nicotine-plus

  Summary:
    * Connects to the Soulseek network for searching, downloading, and sharing music and files.
    * Offers room chats, user messaging, bandwidth throttling, and extensive filtering options.

  Options:
    nicotine-plus --profile <name>: Load or create a dedicated configuration profile.
    nicotine-plus --portable: Keep configuration inside the installation directory for portable setups.
    nicotine-plus --safe-mode: Start without plugins to troubleshoot crashes.

  Example Usage:
    * `nicotine-plus` -- Launch the Soulseek client with the default profile.
    * `nicotine-plus --profile work` -- Maintain separate settings for different sharing communities.
    * `nicotine-plus --portable` -- Store config alongside the executable for removable media use.
*/
_:
let
  NicotineModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nicotine.extended;
    in
    {
      options.programs.nicotine.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nicotine-plus.";
        };

        package = lib.mkPackageOption pkgs "nicotine-plus" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nicotine = NicotineModule;
}
