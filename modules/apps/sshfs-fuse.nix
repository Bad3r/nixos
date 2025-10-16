{
  flake.nixosModules.apps."sshfs-fuse" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."sshfs-fuse" ];
    };
}
