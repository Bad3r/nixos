{
  flake.nixosModules.apps.xsel =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xsel ];
    };
}
