{
  flake.nixosModules.apps."mkcert" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mkcert ];
    };
}
