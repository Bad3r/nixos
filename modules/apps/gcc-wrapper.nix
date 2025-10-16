{
  flake.nixosModules.apps."gcc-wrapper" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gcc ];
    };
}
