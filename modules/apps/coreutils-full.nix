{
  flake.nixosModules.apps."coreutils-full" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."coreutils-full" ];
    };
}
