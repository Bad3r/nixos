/*
  Package: shfmt
  Description: Shell script formatter supporting sh, bash, mksh, and zsh.
*/

{
  flake.nixosModules.apps.shfmt =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.shfmt ];
    };
}
