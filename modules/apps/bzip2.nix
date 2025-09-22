{
  flake.nixosModules.apps.bzip2 =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.bzip2 ];
    };

  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.bzip2 ];
    };
}
