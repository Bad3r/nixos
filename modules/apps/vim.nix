{
  flake.nixosModules.apps.vim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vim ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vim ];
    };
}
