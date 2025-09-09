{
  flake.homeManagerModules.base =
    { pkgs, lib, ... }:
    {
      # Ensure these land before user-added packages, to allow later overrides
      home.packages = lib.mkBefore (
        with pkgs;
        [
          bat
          eza
          fd
          ripgrep
          tree
        ]
      );
    };
}
