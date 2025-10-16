{
  flake.nixosModules.apps."iputils" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.iputils ];
    };
}
