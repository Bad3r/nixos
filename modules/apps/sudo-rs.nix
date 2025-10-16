{
  flake.nixosModules.apps."sudo-rs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."sudo-rs" ];
    };
}
