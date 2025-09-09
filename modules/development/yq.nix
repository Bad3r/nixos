{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yq ];
    };
}
