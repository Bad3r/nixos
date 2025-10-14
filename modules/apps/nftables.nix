{
  flake.nixosModules.apps."nftables" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nftables ];
    };
}
