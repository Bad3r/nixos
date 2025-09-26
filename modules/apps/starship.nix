{
  flake.nixosModules.apps.starship =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.starship ];
    };
}
