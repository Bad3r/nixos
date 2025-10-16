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
    * `nicotine-plus` — Launch the Soulseek client with the default profile.
    * `nicotine-plus --profile work` — Maintain separate settings for different sharing communities.
    * `nicotine-plus --portable` — Store config alongside the executable for removable media use.
*/

{
  flake.nixosModules.apps.nicotine =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nicotine-plus" ];
    };

}
