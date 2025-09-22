{
  flake.nixosModules.apps.nrm =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodePackages.nrm ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodePackages.nrm ];
    };
}
