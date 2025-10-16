{
  flake.nixosModules.apps."upower" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.upower ];
    };
}
