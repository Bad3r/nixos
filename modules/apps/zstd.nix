{
  flake.nixosModules.apps.zstd =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.zstd ];
    };

  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [ pkgs.zstd ];
    };
}
