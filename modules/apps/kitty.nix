/*
  Package: kitty
  Description: GPU-accelerated cross-platform terminal emulator with tiling, tabs, and remote control.
  Homepage: https://sw.kovidgoyal.net/kitty/
  Documentation: https://sw.kovidgoyal.net/kitty/conf/
  Repository: https://github.com/kovidgoyal/kitty

  Summary:
    * Renders text using OpenGL for high performance and ligature support, offering layout splits, kitten extensions, and remote control sockets.
    * Provides built-in features like Unicode input, graphics protocol, session management, and `kitty +kitten` helper commands.

  Options:
    kitty --config <file>: Launch with a custom configuration file.
    kitty @ <command>: Send remote control commands over the kitty socket.
    kitty +kitten themes: Browse and apply color schemes interactively.
    kitty +kitten ssh <host>: Open ssh sessions with kitty's graphics protocol support.
    kitty --session <file>: Restore a predefined layout with tabs/splits.

  Example Usage:
    * `kitty` — Start the terminal emulator with default configuration.
    * `kitty --config ~/.config/kitty/light.conf` — Launch with an alternate theme/config.
    * `kitty @ set-font-size 14` — Adjust font size on the fly via remote control.
*/

{
  flake.nixosModules.apps.kitty =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [
        (_final: prev: {
          kitty = prev.kitty.overrideAttrs (old: {
            doCheck = false;
            doInstallCheck = false;
            checkPhase = "echo skipping kitty checkPhase";
            installCheckPhase = "true";
            nativeCheckInputs = old.nativeCheckInputs or [ ];
          });
        })
      ];

      environment.systemPackages = [ pkgs.kitty ];
    };
}
