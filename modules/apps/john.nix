{
  flake.nixosModules.apps."john" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.john ];
    };
}
