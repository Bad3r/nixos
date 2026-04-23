/*
  Package: remmina
  Description: Home Manager integration for the Remmina remote desktop client.
  Homepage: https://remmina.org/
  Documentation: https://remmina.gitlab.io/remminadoc.gitlab.io/
  Repository: https://gitlab.com/Remmina/Remmina

  Summary:
    * Keeps Remmina's RDP MIME wiring declarative without inheriting the upstream graphical-session autostart service.

  Options:
    services.remmina.enable: Turn on the Home Manager Remmina integration.
    services.remmina.systemdService.enable: Upstream defaults this to true; this wrapper forces false to prevent boot-time autostart.
    services.remmina.systemdService.startupFlags: Control the flags passed when the optional upstream user service launches Remmina.
    services.remmina.addRdpMimeTypeAssoc: Manage the `application/x-rdp` MIME association from Home Manager.

  Notes:
    * Home Manager exposes Remmina under `services.remmina`, not `programs.remmina`.
    * Upstream Home Manager defaults to a `graphical-session.target` user service with `Restart=on-failure`; this wrapper disables it.
*/
_: {
  flake.homeManagerModules.apps.remmina =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "remmina" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        services.remmina = {
          enable = true;
          systemdService.enable = false;
        };
      };
    };
}
