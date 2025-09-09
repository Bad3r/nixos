{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nemo ];
    };
}
