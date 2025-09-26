{
  flake.nixosModules.apps."minio-client" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."minio-client" ];
    };
}
