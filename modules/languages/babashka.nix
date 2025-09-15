{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      config.environment.systemPackages = [ pkgs.babashka ];
    };
}
