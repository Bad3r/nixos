/*
  Package: kitty
  Description: GPU-accelerated cross-platform terminal emulator with tiling, tabs, and remote control.
  Homepage: https://sw.kovidgoyal.net/kitty/
  Documentation: https://sw.kovidgoyal.net/kitty/conf/
  Repository: https://github.com/kovidgoyal/kitty

  Summary:
    * Renders text with OpenGL, with ligatures, layout splits, kitten extensions, and remote control sockets.
    * Provides Unicode input, a graphics protocol, session management, and `kitty +kitten` helper commands.

  Options:
    kitty --config <file>: Launch with a custom configuration file.
    kitty @ <command>: Send remote control commands over the kitty socket.
    kitty +kitten themes: Browse and apply color schemes interactively.
    kitty +kitten ssh <host>: Open ssh sessions with kitty's graphics protocol support.
    kitty --session <file>: Restore a predefined layout with tabs/splits.
*/
_:
let
  KittyModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.kitty.extended;
      sshUrlHandler = pkgs.callPackage ../../../packages/kitty-ssh-url-handler {
        kitty = cfg.package;
      };
      sshUrlHandlerDesktop = "kitty-ssh-url-handler.desktop";
    in
    {
      options.programs.kitty.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable kitty.";
        };

        package = lib.mkPackageOption pkgs "kitty" { };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            environment.systemPackages = [
              cfg.package
              sshUrlHandler
            ];
            xdg.mime.defaultApplications."x-scheme-handler/ssh" = sshUrlHandlerDesktop;
            xdg.mime.addedAssociations."x-scheme-handler/ssh" = sshUrlHandlerDesktop;
          }
          {
            home-manager.sharedModules = [
              {
                xdg.mimeApps = {
                  enable = true;
                  defaultApplications."x-scheme-handler/ssh" = sshUrlHandlerDesktop;
                  associations.added."x-scheme-handler/ssh" = sshUrlHandlerDesktop;
                };
              }
            ];
          }
        ]
      );
    };
in
{
  flake.nixosModules.apps.kitty = KittyModule;
}
