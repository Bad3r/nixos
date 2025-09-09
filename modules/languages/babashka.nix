{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.babashka ];
    };
}
