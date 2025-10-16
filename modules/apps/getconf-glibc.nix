{
  flake.nixosModules.apps."getconf-glibc" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.getconf ];
    };
}
