{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.kwalletmanager ];
    };
}
