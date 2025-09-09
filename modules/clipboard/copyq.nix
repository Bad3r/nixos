{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        copyq # TODO: remove?
        haskellPackages.greenclip
      ];
    };
}
