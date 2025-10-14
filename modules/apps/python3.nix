{
  flake.nixosModules.apps."python3" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.python3 ];
    };
}
