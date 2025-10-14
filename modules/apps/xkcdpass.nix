{
  flake.nixosModules.apps."xkcdpass" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xkcdpass ];
    };
}
