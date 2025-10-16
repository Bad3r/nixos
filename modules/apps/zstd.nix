{
  flake.nixosModules.apps."zstd" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.zstd ];
    };
}
