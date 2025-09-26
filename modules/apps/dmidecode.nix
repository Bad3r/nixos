{
  flake.nixosModules.apps.dmidecode =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dmidecode ];
    };
}
