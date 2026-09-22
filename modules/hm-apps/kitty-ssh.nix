/*
  Package: kitty-ssh-url-handler Home Manager integration
  Description: Installs and associates the Kitty ssh:// URL handler for the selected NixOS Kitty package.
  Homepage: https://sw.kovidgoyal.net/kitty/kittens/ssh/
  Documentation: https://sw.kovidgoyal.net/kitty/kittens/ssh/

  Summary:
    * Builds the handler against programs.kitty.extended.package and installs its desktop entry.
    * Registers both the default and added x-scheme-handler/ssh user associations.
    * Uses the desktop entry's absolute store path, independent of the activation environment's PATH.
    * Rejections produce a critical notification, while notification delivery failures remain nonfatal.
    * The authority is validated without decoding; the unused path is discarded and may contain percent encoding.
    * Accepted URLs run `kitty --hold kitten ssh`, so the window remains after failures and normal exits.

  Example Usage:
    * `kitty-ssh-url-handler ssh://user@host:2222/path` - runs kitty --hold kitten ssh -p 2222 -- user@host
*/
_: {
  flake.homeManagerModules.apps."kitty-ssh" =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "kitty" "extended" "enable" ] false osConfig;
      kittyPackage = lib.attrByPath [ "programs" "kitty" "extended" "package" ] pkgs.kitty osConfig;
      handler = pkgs.callPackage ../../packages/kitty-ssh-url-handler {
        kitty = kittyPackage;
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        home.packages = [ handler ];

        xdg.mimeApps = {
          enable = true;
          defaultApplications."x-scheme-handler/ssh" = "kitty-ssh-url-handler.desktop";
          associations.added."x-scheme-handler/ssh" = "kitty-ssh-url-handler.desktop";
        };
      };
    };
}
