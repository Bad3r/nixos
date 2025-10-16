{
  flake.nixosModules.apps."fail2ban" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.fail2ban ];
    };
}
