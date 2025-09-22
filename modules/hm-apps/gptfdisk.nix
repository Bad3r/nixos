{
  flake.homeManagerModules.apps.gptfdisk =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.gptfdisk ];
    };
}
