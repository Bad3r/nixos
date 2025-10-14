{
  flake.nixosModules.apps."audit" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.audit ];
    };
}
