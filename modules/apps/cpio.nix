{
  flake.nixosModules.apps."cpio" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cpio ];
    };
}
