{
  flake.nixosModules.apps."glibc" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.glibc ];
    };
}
