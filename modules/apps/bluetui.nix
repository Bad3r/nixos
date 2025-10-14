{
  flake.nixosModules.apps."bluetui" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bluetui ];
    };
}
