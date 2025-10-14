{
  flake.nixosModules.apps."acl" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.acl ];
    };
}
