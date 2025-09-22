{
  flake.nixosModules.apps.xz =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.xz ];
    };

  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.xz ];
    };
}
