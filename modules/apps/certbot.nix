{
  flake.nixosModules.apps."certbot" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.certbot ];
    };
}
