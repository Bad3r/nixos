{
  flake.nixosModules.apps."socat" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.socat ];
    };
}
