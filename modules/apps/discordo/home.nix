/*
  Package: discordo
  Description: Discord terminal client with keyboard-driven navigation.

  Notes:
    * notifications.command plays Discord's message sound; the option comes from a patch in the
      Bad3r/nixpkgs fork.
*/

_: {
  flake.homeManagerModules.apps.discordo =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "discordo" "extended" "enable" ] false osConfig;
      # message1.mp3, the Discord client's message notification sound.
      messageSound = pkgs.fetchurl {
        name = "discord-message1.mp3";
        url = "https://discord.com/assets/3ed22d14f3c30bc4.mp3";
        hash = "sha256-Ma0Egu7ndwWXuKpyOoD9BBreCwdmebEik2ZPHxd3IRs=";
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        xdg.configFile."discordo/config.toml".source =
          (pkgs.formats.toml { }).generate "discordo-config.toml"
            {
              notifications.command = "${lib.getExe' pkgs.pipewire "pw-play"} ${messageSound}";
            };
      };
    };
}
