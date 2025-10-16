{
  flake.nixosModules.apps."btrfs-progs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."btrfs-progs" ];
    };
}
