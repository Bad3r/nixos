{
  flake.nixosModules.apps."openssh" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openssh ];
    };
}
