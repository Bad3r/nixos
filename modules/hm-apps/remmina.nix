/*
  Package: remmina
  Description: Home Manager integration for the Remmina remote desktop client.
  Homepage: https://remmina.org/
  Documentation: https://remmina.gitlab.io/remminadoc.gitlab.io/
  Repository: https://gitlab.com/Remmina/Remmina

  Summary:
    * Enables Home Manager's `services.remmina` module only when the corresponding NixOS app module is enabled.
    * Keeps Remmina's user service and RDP MIME wiring declarative while the NixOS layer provides the package.

  Options:
    services.remmina.enable: Turn on the Home Manager Remmina integration and user service.
    services.remmina.systemdService.startupFlags: Control the flags passed when the user service launches Remmina.
    services.remmina.addRdpMimeTypeAssoc: Manage the `application/x-rdp` MIME association from Home Manager.

  Notes:
    * Home Manager exposes Remmina under `services.remmina`, not `programs.remmina`.
    * The upstream Home Manager `package` option is not nullable, so this wrapper omits it and relies on the default package when enabled.
*/
_: {
  flake.homeManagerModules.apps.remmina =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "remmina" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        services.remmina.enable = true;
      };
    };
}
