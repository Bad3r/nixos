{
  flake.nixosModules.apps."accountsservice" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.accountsservice ];
    };
}
