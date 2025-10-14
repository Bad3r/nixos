/*
  Package: ShellCheck
  Description: Static analysis tool for shell scripts.
*/

{
  flake.nixosModules.apps."ShellCheck" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.shellcheck ];
    };
}
