{ lib, ... }:
let
  graphicsModule =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.pc.graphics-support;
    in
    {
      options.pc.graphics-support.enable =
        lib.mkEnableOption "Enable generic graphics support packages"
        // {
          default = true;
        };

      config = lib.mkIf cfg.enable {
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with pkgs; [
            mesa
            libva
            libvdpau
            libglvnd
          ];
          extraPackages32 = with pkgs.pkgsi686Linux; [
            mesa
            libva
            libvdpau
            libglvnd
          ];
        };

        environment.systemPackages = lib.mkAfter [ pkgs.libva-utils ];
      };
    };
in
{
  flake.nixosModules.roles.system.display.x11.imports = lib.mkAfter [ graphicsModule ];
}
