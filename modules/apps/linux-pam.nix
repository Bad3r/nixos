{
  flake.nixosModules.apps."linux-pam" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."linux-pam" ];
    };
}
