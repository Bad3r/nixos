{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
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
}
