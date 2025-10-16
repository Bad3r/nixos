{
  flake.nixosModules.apps."nvidia-settings" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      kernelPackages = config.boot.kernelPackages or pkgs.linuxPackages;
      nvidiaPackages = kernelPackages.nvidiaPackages or pkgs.linuxPackages.nvidiaPackages;
      candidate = pkg: if pkg != null && pkg ? settings then pkg.settings else null;
      pkg = lib.findFirst (p: p != null) null [
        (candidate (nvidiaPackages.production or null))
        (candidate (nvidiaPackages.stable or null))
        (candidate (nvidiaPackages.latest or null))
      ];
    in
    lib.mkIf (pkg != null) {
      environment.systemPackages = [ pkg ];
    };
}
