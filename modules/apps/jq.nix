{
  flake.nixosModules.apps.jq =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jq ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jq ];
    };
}
