{
  flake.homeManagerModules.apps.bitwarden =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.bitwarden ];
    };
}
