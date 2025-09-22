{
  flake.homeManagerModules.apps.copyq =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        copyq
        haskellPackages.greenclip
      ];
    };
}
