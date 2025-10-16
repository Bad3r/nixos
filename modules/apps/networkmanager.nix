{
  flake.nixosModules.apps."networkmanager" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager ];
    };
}
