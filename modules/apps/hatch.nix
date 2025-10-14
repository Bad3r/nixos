{
  flake.nixosModules.apps."hashcat" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hashcat ];
    };
}
