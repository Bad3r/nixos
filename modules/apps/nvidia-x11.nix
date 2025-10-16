{
  flake.nixosModules.apps."nvidia-x11" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      kernelPackages = config.boot.kernelPackages or pkgs.linuxPackages;
      nvidiaPackages = kernelPackages.nvidiaPackages or pkgs.linuxPackages.nvidiaPackages;
      pkg = lib.findFirst (p: p != null) null [
        (nvidiaPackages.production or null)
        (nvidiaPackages.stable or null)
        (nvidiaPackages.latest or null)
      ];
    in
    lib.mkIf (pkg != null) {
      environment.systemPackages = [ pkg ];
    };
}
