_: {
  flake.nixosModules.workstation =
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

        # Tools for VA-API diagnostics (vainfo)
        environment.systemPackages = lib.mkAfter [ pkgs.libva-utils ];
      };
    };
}
