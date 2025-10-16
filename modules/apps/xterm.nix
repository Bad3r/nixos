{
  flake.nixosModules.apps."xterm" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xterm" ];
    };
}
