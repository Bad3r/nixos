{
  flake.nixosModules.apps."sops" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.sops ];
    };
}
