{
  flake.nixosModules.apps."kexec-tools" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."kexec-tools" ];
    };
}
