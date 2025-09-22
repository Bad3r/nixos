{
  flake.nixosModules.apps.unzip =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.unzip ];
    };

  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.unzip ];
    };
}
