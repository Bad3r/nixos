{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_22 ];
    };
}
