{
  flake.nixosModules.apps.ntfs3g =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ntfs3g ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ntfs3g ];
    };
}
