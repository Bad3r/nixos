# Module: home/base/nix-utils.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{ withSystem, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.system = pkgs.writeShellScriptBin "system" "nix-instantiate --eval --expr builtins.currentSystem --raw";
    };
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages =
        (with pkgs; [
          nix-output-monitor
          nix-fast-build
          nix-tree
          nvd
          nix-diff
        ])
        ++ [
          (withSystem pkgs.system (psArgs: psArgs.config.packages.system))
        ];
      programs.nh.enable = true;
    };
}
