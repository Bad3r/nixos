{
  flake.nixosModules.apps."age" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.age ];
    };
}
