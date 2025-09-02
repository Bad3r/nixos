_: {
  flake.modules.nixos.pc =
    { pkgs, lib, ... }:
    {
      # Enable OpenGL/Graphics support for desktop applications
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

      # Environment variables for proper graphics rendering
      environment.variables = {
        # Force software rendering if hardware acceleration fails
        LIBGL_ALWAYS_SOFTWARE = lib.mkDefault "0";
        # Enable VA-API for video acceleration (can be overridden per-host)
        LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
      };
    };
}
