{
  flake.nixosModules.apps."getent-glibc" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.getent ];
    };
}
