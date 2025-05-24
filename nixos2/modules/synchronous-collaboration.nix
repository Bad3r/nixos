# modules/synchronous-collaboration.nix

{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        mob # https://github.com/remotemobprogramming/mob
      ];
    };
}
