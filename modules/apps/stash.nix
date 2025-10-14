{
  flake.nixosModules.apps."stash" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."stash" ];
    };
}
