{
  flake.nixosModules.apps."rsync" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rsync ];
    };
}
