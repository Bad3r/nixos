{
  flake.nixosModules.apps.awscli2 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.awscli2 ];
    };
}
