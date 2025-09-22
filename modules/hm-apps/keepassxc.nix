{
  flake.homeManagerModules.apps.keepassxc =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.keepassxc ];
    };
}
