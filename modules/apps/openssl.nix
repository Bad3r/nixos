{
  flake.nixosModules.apps."openssl" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openssl ];
    };
}
