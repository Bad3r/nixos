{
  flake.nixosModules.apps.procps =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.procps ];
    };
}
