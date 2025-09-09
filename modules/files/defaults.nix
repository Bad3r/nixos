{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        bat
        eza
        fd
        ripgrep
        tree
      ];
    };
}
