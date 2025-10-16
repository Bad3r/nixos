{
  flake.nixosModules.apps."vt-cli" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."vt-cli" ];
    };
}
