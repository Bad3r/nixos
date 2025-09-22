{
  flake.nixosModules.apps."tor-browser" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tor-browser ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tor-browser ];
    };
}
