{
  flake.nixosModules.apps."mosh" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mosh ];
    };
}
