{
  flake.nixosModules.apps."shadow" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.shadow ];
    };
}
