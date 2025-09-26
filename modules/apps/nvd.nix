{
  flake.nixosModules.apps.nvd =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nvd ];
    };
}
