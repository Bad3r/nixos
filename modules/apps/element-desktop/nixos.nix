/*
  Package: element-desktop
  Description: Matrix.org secure collaboration client with end-to-end encryption.
  Homepage: https://element.io/
  Documentation: https://element.io/help
  Repository: https://github.com/element-hq/element-web

  Summary:
    * Connects to Matrix homeservers for encrypted chats, voice and video calls, and spaces.
    * Supports cross-signing and bridges to other chat networks.

  Options:
    element-desktop --profile <name>: Launch with a specific profile directory.
    element-desktop --proxy-server=<url>: Send traffic through an HTTP/SOCKS proxy.
    element-desktop --enable-features=UseOzonePlatform: Enable Wayland-friendly rendering.
*/
_:
let
  ElementDesktopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."element-desktop".extended;
    in
    {
      options.programs.element-desktop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable element-desktop.";
        };

        package = lib.mkPackageOption pkgs "element-desktop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.element-desktop = ElementDesktopModule;
}
